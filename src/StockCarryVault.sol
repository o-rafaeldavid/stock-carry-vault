// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {ISpoke} from "src/interfaces/aave/ISpoke.sol";
import {IPool} from "src/interfaces/aave/IPool.sol";
import {IPriceOracle} from "src/interfaces/aave/IPriceOracle.sol";

/// @title StockCarryVault
/// @notice Personal ERC-4626 vault that holds a tokenized stock (e.g. NVDAc) as collateral on
///         Aave V4, borrows USDC against it at a low LTV and parks that USDC on Aave V3.
///         Shares (stpNVDA) are denominated in the stock: their value in the stock rises with
///         the supply incentives and the carry (Aave V3 yield minus borrow cost).
/// @dev    Only the owner deposits and withdraws. A keeper may run maintenance (rebalance,
///         buys within budget, emergency deleverage) but can never move funds out of the vault.
///         Not upgradeable: a logic change means deploying a new vault and migrating.
contract StockCarryVault is ERC4626, Ownable2Step {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------------
    // Immutables
    // ---------------------------------------------------------------------

    /// @notice Aave V4 spoke holding the collateral and the USDC debt ("Coinbase Stocks" on Base).
    ISpoke public immutable spoke;
    /// @notice Aave V3 pool where the borrowed USDC is parked.
    IPool public immutable poolV3;
    /// @notice Debt token (USDC, 6 decimals).
    IERC20 public immutable usdc;
    /// @notice Aave V3 receipt for parked USDC (aBasUSDC); its balance grows with interest.
    IERC20 public immutable aUsdc;
    /// @notice Spoke reserve id of the collateral (5 = NVDAc on the Coinbase Stocks spoke).
    uint256 public immutable collateralId;
    /// @notice Spoke reserve id of the debt asset (7 = USDC on the Coinbase Stocks spoke).
    uint256 public immutable debtId;

    // ---------------------------------------------------------------------
    // Roles and risk parameters
    // ---------------------------------------------------------------------

    /// @notice Hot key (e.g. a bot on Koyeb) allowed to run maintenance. Cannot withdraw.
    address public keeper;

    /// @notice LTV bands, in basis points of debt / collateral value (2500 = 25%).
    /// @dev Must satisfy lower < target < upper < emergency < 7000 (Aave V4 liquidation line for NVDAc).
    struct Params {
        uint16 targetBps; // LTV restored after every rebalance
        uint16 lowerBps; // below this, borrow back up to target
        uint16 upperBps; // above this, repay from the USDC reserve back to target
        uint16 emergencyBps; // above this, sell collateral to repay and pause deposits
    }

    /// @notice Current LTV bands.
    Params public params;

    // ---------------------------------------------------------------------
    // Errors and events
    // ---------------------------------------------------------------------

    /// @notice Caller is neither the keeper nor the owner.
    error NotKeeper();
    /// @notice LTV bands are out of order or reach the liquidation line.
    error BadParams();
    /// @notice A reserve id does not point to the expected token on the spoke.
    error WrongReserve();

    /// @notice Emitted when the keeper changes.
    event KeeperSet(address keeper);
    /// @notice Emitted when the LTV bands change.
    event ParamsSet(Params p);

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    /// @param _asset        Collateral token, also the ERC-4626 asset (NVDAc).
    /// @param _spoke        Aave V4 spoke.
    /// @param _poolV3       Aave V3 pool used to park USDC.
    /// @param _usdc         USDC.
    /// @param _aUsdc        Aave V3 aToken for USDC (aBasUSDC).
    /// @param _collateralId Spoke reserve id of `_asset`.
    /// @param _debtId       Spoke reserve id of `_usdc`.
    /// @param _owner        Admin and only depositor (a Safe in production).
    /// @param _keeper       Maintenance bot.
    /// @dev Reverts with WrongReserve if either id does not match its token, so a wrong id
    ///      can never be deployed. Starts with bands 25% / 19% / 32% / 45%.
    constructor(
        IERC20 _asset,
        ISpoke _spoke,
        IPool _poolV3,
        IERC20 _usdc,
        IERC20 _aUsdc,
        uint256 _collateralId,
        uint256 _debtId,
        address _owner,
        address _keeper
    ) ERC20("Staked NVDA (personal)", "stpNVDA") ERC4626(_asset) Ownable(_owner) {
        spoke = _spoke;
        poolV3 = _poolV3;
        usdc = _usdc;
        aUsdc = _aUsdc;
        collateralId = _collateralId;
        debtId = _debtId;
        keeper = _keeper;
        emit KeeperSet(_keeper);

        if (_spoke.getReserve(_collateralId).underlying != address(_asset)) revert WrongReserve();
        if (_spoke.getReserve(_debtId).underlying != address(_usdc)) revert WrongReserve();

        _setParams(Params({targetBps: 2500, lowerBps: 1900, upperBps: 3200, emergencyBps: 4500}));
    }

    // ---------------------------------------------------------------------
    // Access control
    // ---------------------------------------------------------------------

    /// @dev Restricts maintenance functions to the keeper or the owner.
    modifier onlyKeeperOrOwner() {
        if (msg.sender != keeper && msg.sender != owner()) revert NotKeeper();
        _;
    }

    // ---------------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------------

    /// @notice Replaces the keeper. Set to address(0) to disable automation.
    function setKeeper(address k) external onlyOwner {
        keeper = k;
        emit KeeperSet(k);
    }

    /// @notice Updates the LTV bands.
    function setParams(Params calldata p) external onlyOwner {
        _setParams(p);
    }

    /// @dev Validates the band order and stores it.
    function _setParams(Params memory p) internal {
        bool ok = p.lowerBps < p.targetBps && p.targetBps < p.upperBps && p.upperBps < p.emergencyBps
            && p.emergencyBps < 7000;
        if (!ok) revert BadParams();
        params = p;
        emit ParamsSet(p);
    }
}
