// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

import {ISpoke} from "src/interfaces/aave/ISpoke.sol";
import {IPool} from "src/interfaces/aave/IPool.sol";
import {IPriceOracle} from "src/interfaces/aave/IPriceOracle.sol";

contract StockCarryVault is ERC4626, Ownable2Step {
    // imutables
    ISpoke public immutable spoke;
    IPool public immutable poolV3;
    IERC20 public immutable usdc;
    IERC20 public immutable aUsdc;
    uint256 public immutable collateralId;
    uint256 public immutable debtId;

    // keeper and params
    address public keeper;
    struct Params {
        uint16 targetBps;
        uint16 lowerBps;
        uint16 upperBps;
        uint16 emergencyBps;
    }
    Params public params;

    // errors and events
    error NotKeeper();
    error BadParams();
    error WrongReserve();
    event KeeperSet(address keeper);
    event ParamsSet(Params p);

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
    )
        ERC20("Staked NVDA (personal)", "stpNVDA")
        ERC4626(_asset)
        Ownable(_owner)
    {
        spoke = _spoke;
        poolV3 = _poolV3;
        usdc = _usdc;
        aUsdc = _aUsdc;
        collateralId = _collateralId;
        debtId = _debtId;
        keeper = _keeper;

        emit KeeperSet(_keeper);

        if (_spoke.getReserve(_collateralId).underlying != address(_asset)) {
            revert WrongReserve();
        }
        if (_spoke.getReserve(_debtId).underlying != address(_usdc)) {
            revert WrongReserve();
        }

        _setParams(Params(2500, 1900, 3200, 4500));
    }

    modifier onlyKeeperOrOwner() {
        if (msg.sender != keeper && msg.sender != owner()) {
            revert NotKeeper();
        }
        _;
    }

    function setKeeper(address k) external onlyOwner {}

    function _setParams(Params memory p) internal {
        bool ok = p.lowerBps < p.targetBps &&
            p.targetBps < p.upperBps &&
            p.upperBps < p.emergencyBps &&
            p.emergencyBps < 7000;
        if (!ok) {
            revert BadParams();
        }
        params = p;
    }
    function setParams(Params calldata p) external onlyOwner {
        _setParams(p);
    }
}
