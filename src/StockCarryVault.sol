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
    error NotOwner();
    error BadParams();
    error WrongReserve();
    event KeeperSet(address keeper);
    event ParamsSet(Params p);

    constructor(
        asset,
        spoke,
        poolV3,
        usdc,
        aUsdc,
        ids,
        owner,
        keeper
    )
        ERC20("Staked NVDA (personal)", "stpNVDA")
        ERC4626(asset)
        Ownable(owner)
    {}

    modifier onlyKeeperOrOwner() {}

    function setKeeper(address k) external onlyOwner {}

    function setParams(Params calldata p) external onlyOwner {}
}
