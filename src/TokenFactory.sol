// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Token.sol";
import "./BondingCurve.sol";
import "./MockLiquidityPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TokenFactory {
    address public immutable vapor;
    address public immutable liquidityPool;
    uint256 public defaultStartPrice;
    uint256 public defaultTargetVapor;

    event TokenCreated(address token, address bondingCurve, string name, string symbol);

    constructor(address _vapor, address _liquidityPool, uint256 _defaultStartPrice, uint256 _defaultTargetVapor) {
        require(_vapor != address(0), "Invalid VAPOR");
        require(_liquidityPool != address(0), "Invalid liquidity pool");
        require(_defaultStartPrice > 0, "Invalid start price");
        require(_defaultTargetVapor > 0, "Invalid target VAPOR");

        vapor = _vapor;
        liquidityPool = _liquidityPool;
        defaultStartPrice = _defaultStartPrice;
        defaultTargetVapor = _defaultTargetVapor;
    }

    function createToken(string memory name, string memory symbol)
        external
        returns (address tokenAddress, address curveAddress)
    {
        // Deploy new token with liquidityPool as reserve
        Token token = new Token(name, symbol, msg.sender, liquidityPool);

        // Deploy bonding curve
        BondingCurve curve =
            new BondingCurve(address(token), vapor, liquidityPool, defaultStartPrice, defaultTargetVapor);

        // Transfer curve's share to the curve
        uint256 curveAmount = (token.TOTAL_SUPPLY() * token.CURVE_SHARE()) / 100;
        token.transfer(address(curve), curveAmount);

        emit TokenCreated(address(token), address(curve), name, symbol);

        return (address(token), address(curve));
    }

    function updateDefaultParameters(uint256 newStartPrice, uint256 newTargetVapor) external {
        require(newStartPrice > 0, "Invalid start price");
        require(newTargetVapor > 0, "Invalid target VAPOR");

        defaultStartPrice = newStartPrice;
        defaultTargetVapor = newTargetVapor;
    }
}
