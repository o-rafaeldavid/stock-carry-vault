// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// @title ISpoke
/// @author Aave Labs
/// @notice Partial interface for Spoke Aave V4 Contract.
/// @notice Basic partial interface for any price oracle from Aave V4 Contract.
/// @notice Full interface: https://github.com/aave/aave-v4/blob/main/src/spoke/interfaces/IPriceOracle.sol
/// @dev All prices must use the same number of decimals as the oracle and should be returned in the same currency.

interface IPriceOracle {
    /// @notice Returns the number of decimals used to return prices.
    function decimals() external view returns (uint8);

    /// @notice Returns the reserve price with `decimals` precision.
    /// @dev Reverts if the price is not greater than 0.
    /// @param reserveId The identifier of the reserve.
    /// @return The price of the reserve.
    function getReservePrice(uint256 reserveId) external view returns (uint256);
}
