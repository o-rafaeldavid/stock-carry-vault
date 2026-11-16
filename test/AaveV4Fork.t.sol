// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "src/interfaces/aave/IPool.sol";
import {ISpoke} from "src/interfaces/aave/ISpoke.sol";
import {IPriceOracle} from "src/interfaces/aave/IPriceOracle.sol";

contract AaveV4ForkTest is Test {
    address SPOKE = 0x17905Db0e4A3514467539956c084180616AE7B8D;
    address NVDAc = 0xb20000000000000000000078ee7ce2fE4908108C;
    address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address POOL_V3 = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address aBasUSDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB;

    uint256 random_block = 58305067; /* random block in a business day */
    address constant NVDAc_WHALE = 0xEF83ABC641B98af01f0652E3Af49a25d65C601A5; // ~483 NVDAc at this block

    uint256 NVDAc_ID = 5;
    uint256 USDC_ID = 7;
    uint256 AMOUNT = 10e8; // 10 NVDAc
    uint256 constant TARGET_LTV_BPS = 2_500; // 25%

    function setUp() public {
        vm.createSelectFork("base", random_block);
    }

    function test_cycle() public {
        _getNvda();
        _supplyAsCollateral();
        uint256 borrowed = _borrowTarget();
        _parkInV3Pool(borrowed);
        _logPositionState("after loan and borrow");
        _unwind();

        assertApproxEqAbs(
            IERC20(NVDAc).balanceOf(address(this)),
            AMOUNT,
            1,
            "NVDAc doesn't came back"
        );
        assertEq(
            ISpoke(SPOKE).getUserTotalDebt(USDC_ID, address(this)),
            0,
            "ended in debt"
        );
    }

    // ------
    // Reads
    // ------
    function _nvdaPrice() internal view returns (uint256) {
        return IPriceOracle(ISpoke(SPOKE).ORACLE()).getReservePrice(NVDAc_ID);
    }

    function _logPositionState(string memory label) internal view {
        ISpoke.UserAccountData memory a = ISpoke(SPOKE).getUserAccountData(
            address(this)
        );
        console.log("---", label, "---");
        console.log(
            "NVDAc supplied (8 dec)",
            ISpoke(SPOKE).getUserSuppliedAssets(NVDAc_ID, address(this))
        );
        console.log(
            "USDC borrowed (6 dec)     ",
            ISpoke(SPOKE).getUserTotalDebt(USDC_ID, address(this))
        );
        console.log(
            "aBasUSDC (6 dec)        ",
            IERC20(aBasUSDC).balanceOf(address(this))
        );
        console.log("health factor (WAD: 1e18=1.0)", a.healthFactor);
        console.log("avg collateral factor (WAD)   ", a.avgCollateralFactor);
    }

    // ------
    // FLOW
    // ------

    // 1 - get NVDAc
    function _getNvda() internal {
        vm.prank(NVDAc_WHALE);
        IERC20(NVDAc).transfer(address(this), AMOUNT);
        assertEq(IERC20(NVDAc).balanceOf(address(this)), AMOUNT);
    }

    // 2 - supply NVDAc
    function _supplyAsCollateral() internal {
        IERC20(NVDAc).approve(SPOKE, AMOUNT);
        (uint256 shares, uint256 assets) = ISpoke(SPOKE).supply(
            NVDAc_ID,
            AMOUNT,
            address(this)
        );
        ISpoke(SPOKE).setUsingAsCollateral(NVDAc_ID, true, address(this));

        console.log("supply: shares", shares, "assets", assets);
        assertApproxEqAbs(
            ISpoke(SPOKE).getUserSuppliedAssets(NVDAc_ID, address(this)),
            AMOUNT,
            1
        );
        assertEq(IERC20(NVDAc).balanceOf(address(this)), 0);
    }

    // 3 borrow USDC
    function _borrowTarget() internal returns (uint256 usdcAmount) {
        uint256 price = _nvdaPrice();
        uint8 dec = IPriceOracle(ISpoke(SPOKE).ORACLE()).decimals();
        uint256 supplied = ISpoke(SPOKE).getUserSuppliedAssets(
            NVDAc_ID,
            address(this)
        );

        uint256 collateralUSDC = (supplied * price) / (10 ** (8 + dec - 6));
        usdcAmount = (collateralUSDC * TARGET_LTV_BPS) / 10_000;

        console.log("NVDA price (Oracle)", price, "decimals", dec);
        console.log("collateral in USDC", collateralUSDC);
        console.log("to borrow", usdcAmount);

        uint256 before = IERC20(USDC).balanceOf(address(this));
        ISpoke(SPOKE).borrow(USDC_ID, usdcAmount, address(this));
        assertEq(
            IERC20(USDC).balanceOf(address(this)) - before,
            usdcAmount,
            "Not enough USDC"
        );
    }

    // 4 - park USDC on Aave V3
    function _parkInV3Pool(uint256 amount) internal {
        IERC20(USDC).approve(POOL_V3, amount);
        IPool(POOL_V3).supply(USDC, amount, address(this), 0);
        assertApproxEqAbs(IERC20(aBasUSDC).balanceOf(address(this)), amount, 2);
    }

    // 5 - unwind position
    function _unwind() internal {
        IPool(POOL_V3).withdraw(USDC, type(uint256).max, address(this));

        uint256 debt = ISpoke(SPOKE).getUserTotalDebt(USDC_ID, address(this));
        uint256 bal = IERC20(USDC).balanceOf(address(this));
        console.log("debt", debt, "balance USDC", bal);
        if (bal < debt) deal(USDC, address(this), debt);

        IERC20(USDC).approve(SPOKE, debt);
        ISpoke(SPOKE).repay(USDC_ID, debt, address(this));

        ISpoke(SPOKE).withdraw(NVDAc_ID, type(uint256).max, address(this));
    }
}
