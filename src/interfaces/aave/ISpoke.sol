// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// @title ISpoke
/// @author Aave Labs
/// @notice Partial interface for Spoke Aave V4 Contract.
/// @notice Full interface: https://github.com/aave/aave-v4/blob/main/src/spoke/interfaces/ISpoke.sol

interface ISpoke {
    /// @notice User account data describing a user position and its health.
    /// @dev riskPremium The risk premium of the user position, expressed in BPS.
    /// @dev avgCollateralFactor The weighted average collateral factor of the user position, expressed in WAD.
    /// @dev healthFactor The health factor of the user position, expressed in WAD. 1e18 represents a health factor of 1.00.
    /// @dev totalCollateralValue The total collateral value of the user position, expressed in units of Value.
    /// @dev totalDebtValueRay The total debt value of the user position, expressed in units of Value and scaled by RAY.
    /// @dev activeCollateralCount The number of active collaterals, which includes reserves with `collateralFactor` > 0, `enabledAsCollateral` and `suppliedAmount` > 0.
    /// @dev borrowCount The number of borrowed reserves of the user position.
    struct UserAccountData {
        uint256 riskPremium;
        uint256 avgCollateralFactor;
        uint256 healthFactor;
        uint256 totalCollateralValue;
        uint256 totalDebtValueRay;
        uint256 activeCollateralCount;
        uint256 borrowCount;
    }

    /// @notice Supplies an amount of underlying asset of the specified reserve.
    /// @dev It reverts if the reserve associated with the given reserve identifier is not listed.
    /// @dev The Spoke pulls the underlying asset from the caller, so prior token approval is required.
    /// @dev Caller must be `onBehalfOf` or an authorized position manager for `onBehalfOf`.
    /// @param reserveId The reserve identifier.
    /// @param amount The amount of asset to supply.
    /// @param onBehalfOf The owner of the position to add supply shares to.
    /// @return The amount of shares supplied.
    /// @return The amount of assets supplied.
    function supply(
        uint256 reserveId,
        uint256 amount,
        address onBehalfOf
    ) external returns (uint256, uint256);

    /// @notice Withdraws a specified amount of underlying asset from the given reserve.
    /// @dev It reverts if the reserve associated with the given reserve identifier is not listed.
    /// @dev Providing an amount greater than the maximum withdrawable value signals a full withdrawal.
    /// @dev Caller must be `onBehalfOf` or an authorized position manager for `onBehalfOf`.
    /// @dev Caller receives the underlying asset withdrawn.
    /// @param reserveId The identifier of the reserve.
    /// @param amount The amount of asset to withdraw.
    /// @param onBehalfOf The owner of position to remove supply shares from.
    /// @return The amount of shares withdrawn.
    /// @return The amount of assets withdrawn.
    function withdraw(
        uint256 reserveId,
        uint256 amount,
        address onBehalfOf
    ) external returns (uint256, uint256);

    /// @notice Borrows a specified amount of underlying asset from the given reserve.
    /// @dev It reverts if the reserve associated with the given reserve identifier is not listed.
    /// @dev It reverts if the user would borrow more than the maximum allowed number of borrowed reserves.
    /// @dev Caller must be `onBehalfOf` or an authorized position manager for `onBehalfOf`.
    /// @dev Caller receives the underlying asset borrowed.
    /// @param reserveId The identifier of the reserve.
    /// @param amount The amount of asset to borrow.
    /// @param onBehalfOf The owner of the position against which debt is generated.
    /// @return The amount of shares borrowed.
    /// @return The amount of assets borrowed.
    function borrow(
        uint256 reserveId,
        uint256 amount,
        address onBehalfOf
    ) external returns (uint256, uint256);

    /// @notice Repays a specified amount of underlying asset to a given reserve.
    /// @dev It reverts if the reserve associated with the given reserve identifier is not listed.
    /// @dev The Spoke pulls the underlying asset from the caller, so prior approval is required.
    /// @dev Caller must be `onBehalfOf` or an authorized position manager for `onBehalfOf`.
    /// @param reserveId The identifier of the reserve.
    /// @param amount The amount of asset to repay.
    /// @param onBehalfOf The owner of the position whose debt is repaid.
    /// @return The amount of shares repaid.
    /// @return The amount of assets repaid.
    function repay(
        uint256 reserveId,
        uint256 amount,
        address onBehalfOf
    ) external returns (uint256, uint256);

    /// @notice Allows suppliers to enable/disable a specific supplied reserve as collateral.
    /// @dev It reverts if the reserve associated with the given reserve identifier is not listed.
    /// @dev It reverts if the user exceeds the maximum allowed collateral reserves when enabling.
    /// @dev Reserves with zero supplied or zero collateral factor count towards the max allowed collateral reserves.
    /// @dev Caller must be `onBehalfOf` or an authorized position manager for `onBehalfOf`.
    /// @param reserveId The reserve identifier of the underlying asset.
    /// @param usingAsCollateral True if the user wants to use the supply as collateral.
    /// @param onBehalfOf The owner of the position being modified.
    function setUsingAsCollateral(
        uint256 reserveId,
        bool usingAsCollateral,
        address onBehalfOf
    ) external;

    /// @notice Returns the amount of assets supplied by a specific user for a given reserve.
    /// @dev It reverts if the reserve associated with the given reserve identifier is not listed.
    /// @param reserveId The identifier of the reserve.
    /// @param user The address of the user.
    /// @return The amount of assets supplied by the user.
    function getUserSuppliedAssets(
        uint256 reserveId,
        address user
    ) external view returns (uint256);

    /// @notice Returns the total debt of a specific user for a given reserve.
    /// @dev It reverts if the reserve associated with the given reserve identifier is not listed.
    /// @dev The total debt of the user is the sum of drawn debt and premium debt.
    /// @param reserveId The identifier of the reserve.
    /// @param user The address of the user.
    /// @return The total debt amount.
    function getUserTotalDebt(
        uint256 reserveId,
        address user
    ) external view returns (uint256);

    /// @notice Returns the most up-to-date user account data information.
    /// @dev Utilizes user's current dynamic configuration of user position.
    /// @param user The address of the user.
    /// @return The user account data struct.
    function getUserAccountData(
        address user
    ) external view returns (UserAccountData memory);

    /// @notice Returns the address of the AaveOracle contract.
    function ORACLE() external view returns (address);
}
