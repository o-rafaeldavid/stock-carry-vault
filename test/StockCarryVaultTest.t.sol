// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StockCarryVault} from "src/StockCarryVault.sol";
import {ISpoke} from "src/interfaces/aave/ISpoke.sol";
import {IPool} from "src/interfaces/aave/IPool.sol";
import {IPriceOracle} from "src/interfaces/aave/IPriceOracle.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract StockCarryVaultTest is Test {
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

    StockCarryVault vault;
    address keeper = makeAddr("keeper");
    address user = makeAddr("user");

    function setUp() public {
        vm.createSelectFork("base", random_block);
        // deploy vault
        vault = new StockCarryVault(
            IERC20(NVDAc),
            ISpoke(SPOKE),
            IPool(POOL_V3),
            IERC20(USDC),
            IERC20(aBasUSDC),
            NVDAc_ID,
            USDC_ID,
            address(this),
            keeper
        );
    }

    function test_deployState() public {
        assertEq(vault.owner(), address(this));
        assertEq(vault.keeper(), keeper);

        assertEq(vault.asset(), NVDAc);
        assertEq(address(vault.spoke()), SPOKE);
        assertEq(address(vault.poolV3()), POOL_V3);
        assertEq(address(vault.usdc()), USDC);
        assertEq(address(vault.aUsdc()), aBasUSDC);
        assertEq(vault.collateralId(), NVDAc_ID);
        assertEq(vault.debtId(), USDC_ID);

        assertEq(vault.symbol(), "stpNVDA");
        assertEq(vault.decimals(), IERC20Metadata(NVDAc).decimals());

        (uint16 target, uint16 lower, uint16 upper, uint16 emergency) = vault
            .params();
        assertEq(target, 2500);
        assertEq(lower, 1900);
        assertEq(upper, 3200);
        assertEq(emergency, 4500);

        assertEq(vault.totalSupply(), 0);
    }

    function test_paramsOnlyOwner() public {
        StockCarryVault.Params memory p = StockCarryVault.Params({
            targetBps: 2500,
            lowerBps: 1900,
            upperBps: 3200,
            emergencyBps: 4500
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user
            )
        );
        vm.prank(user);
        vault.setParams(p);
    }

    function test_badParamsReverts() public {
        StockCarryVault.Params memory p_lowerBig = StockCarryVault.Params({
            targetBps: 1900,
            lowerBps: 2500,
            upperBps: 3200,
            emergencyBps: 4500
        });

        StockCarryVault.Params memory p_upperLow = StockCarryVault.Params({
            targetBps: 2500,
            lowerBps: 1900,
            upperBps: 0,
            emergencyBps: 4500
        });

        StockCarryVault.Params memory p_emergencyLow = StockCarryVault.Params({
            targetBps: 2500,
            lowerBps: 1900,
            upperBps: 3200,
            emergencyBps: 0
        });

        StockCarryVault.Params memory p_emergencyLiquidation = StockCarryVault
            .Params({
                targetBps: 2500,
                lowerBps: 1900,
                upperBps: 3200,
                emergencyBps: 7000
            });

        vm.expectRevert(StockCarryVault.BadParams.selector);
        vault.setParams(p_lowerBig);

        vm.expectRevert(StockCarryVault.BadParams.selector);
        vault.setParams(p_upperLow);

        vm.expectRevert(StockCarryVault.BadParams.selector);
        vault.setParams(p_emergencyLow);

        vm.expectRevert(StockCarryVault.BadParams.selector);
        vault.setParams(p_emergencyLiquidation);
    }

    function test_wrongReserveReverts() public {
        vm.expectRevert(StockCarryVault.WrongReserve.selector);
        new StockCarryVault(
            IERC20(NVDAc),
            ISpoke(SPOKE),
            IPool(POOL_V3),
            IERC20(USDC),
            IERC20(aBasUSDC),
            USDC_ID, // <- error (not NVDAc_ID)
            USDC_ID,
            address(this),
            keeper
        );
    }

    function test_totalAssets_matchesPosition() public {
        vm.prank(NVDAc_WHALE);
        IERC20(NVDAc).transfer(address(vault), AMOUNT);

        _supplyAsCollateral();
        uint256 usdcAmount = _borrowTarget();
        _parkInV3Pool(usdcAmount);
    }

    // ------
    // Reads
    // ------
    function _nvdaPrice() internal view returns (uint256) {
        return IPriceOracle(ISpoke(SPOKE).ORACLE()).getReservePrice(NVDAc_ID);
    }

    // ------
    // Flow
    // ------

    function _supplyAsCollateral() internal {
        vm.startPrank(address(vault));
        IERC20(NVDAc).approve(SPOKE, AMOUNT);
        (uint256 shares, uint256 assets) = ISpoke(SPOKE).supply(
            NVDAc_ID,
            AMOUNT,
            address(vault)
        );
        ISpoke(SPOKE).setUsingAsCollateral(NVDAc_ID, true, address(vault));

        console.log("supply: shares", shares, "assets", assets);
        assertApproxEqAbs(
            ISpoke(SPOKE).getUserSuppliedAssets(NVDAc_ID, address(vault)),
            AMOUNT,
            1
        );
        assertEq(IERC20(NVDAc).balanceOf(address(vault)), 0);
    }

    function _borrowTarget() internal returns (uint256 usdcAmount) {
        uint256 price = _nvdaPrice();
        uint8 dec = IPriceOracle(ISpoke(SPOKE).ORACLE()).decimals();
        uint256 supplied = ISpoke(SPOKE).getUserSuppliedAssets(
            NVDAc_ID,
            address(vault)
        );

        uint256 collateralUSDC = (supplied * price) / (10 ** (8 + dec - 6));
        usdcAmount = (collateralUSDC * TARGET_LTV_BPS) / 10_000;

        console.log("NVDA price (Oracle)", price, "decimals", dec);
        console.log("collateral in USDC", collateralUSDC);
        console.log("to borrow", usdcAmount);

        uint256 before = IERC20(USDC).balanceOf(address(vault));
        ISpoke(SPOKE).borrow(USDC_ID, usdcAmount, address(vault));
        assertEq(
            IERC20(USDC).balanceOf(address(vault)) - before,
            usdcAmount,
            "Not enough USDC"
        );
    }

    function _parkInV3Pool(uint256 amount) internal {
        IERC20(USDC).approve(POOL_V3, amount);
        IPool(POOL_V3).supply(USDC, amount, address(vault), 0);
        assertApproxEqAbs(
            IERC20(aBasUSDC).balanceOf(address(vault)),
            amount,
            2
        );
    }
}
