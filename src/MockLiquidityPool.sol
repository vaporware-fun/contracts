// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./Token.sol";

contract MockLiquidityPool {
    using SafeERC20 for IERC20;

    event PoolCreated(address token, address vapor, uint256 tokenAmount, uint256 vaporAmount);

    // Simple function to simulate creating a liquidity pool
    function createPool(address token, address vapor, uint256 tokenAmount, uint256 vaporAmount) external {
        // Transfer tokens from reserve to this contract
        IERC20(token).safeTransferFrom(Token(token).reserve(), address(this), tokenAmount);

        // Transfer VAPOR from curve to this contract
        IERC20(vapor).safeTransferFrom(msg.sender, address(this), vaporAmount);

        emit PoolCreated(token, vapor, tokenAmount, vaporAmount);
    }

    // View functions to check balances
    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function getVaporBalance(address vapor) external view returns (uint256) {
        return IERC20(vapor).balanceOf(address(this));
    }
}
