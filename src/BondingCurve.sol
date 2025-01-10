// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./MockLiquidityPool.sol";
import "./Token.sol";

contract BondingCurve is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    IERC20 public immutable vapor;
    MockLiquidityPool public immutable liquidityPool;

    uint256 public immutable startPrice;
    uint256 public immutable targetVapor;
    uint256 public constant PRECISION = 1e18;

    // Curve parameters
    uint256 public constant EXPONENT = 2; // Quadratic curve
    uint256 public tokensSold;
    uint256 public vaporCollected;
    bool public tradingActive = true;
    bool public hasGraduated;

    event TokensPurchased(address buyer, uint256 tokenAmount, uint256 vaporAmount);
    event TokensSold(address seller, uint256 tokenAmount, uint256 vaporAmount);
    event CurveGraduated(uint256 tokenAmount, uint256 vaporAmount);

    error InvalidAmount();
    error TradingStopped();
    error InvalidReturn();
    error InsufficientVAPOR();
    error AlreadyGraduated();
    error NotReadyToGraduate();
    error TransferFailed();

    constructor(address _token, address _vapor, address _liquidityPool, uint256 _startPrice, uint256 _targetVapor) {
        require(_token != address(0), "Invalid token");
        require(_vapor != address(0), "Invalid VAPOR");
        require(_liquidityPool != address(0), "Invalid liquidity pool");
        require(_startPrice > 0, "Invalid start price");
        require(_targetVapor > 0, "Invalid target VAPOR");

        token = IERC20(_token);
        vapor = IERC20(_vapor);
        liquidityPool = MockLiquidityPool(_liquidityPool);
        startPrice = _startPrice;
        targetVapor = _targetVapor;
    }

    function getCurrentPrice() public view returns (uint256) {
        uint256 remainingSupply = token.balanceOf(address(this)) - tokensSold;
        uint256 totalSupply = token.balanceOf(address(this));
        require(totalSupply > 0, "No tokens in curve");

        // Price increases quadratically as remaining supply decreases
        return startPrice * (PRECISION + (EXPONENT * (totalSupply - remainingSupply) * PRECISION) / totalSupply)
            / PRECISION;
    }

    function buyTokens(uint256 vaporAmount) external nonReentrant {
        if (vaporAmount == 0) revert InvalidAmount();
        if (!tradingActive) revert TradingStopped();
        if (hasGraduated) revert AlreadyGraduated();

        uint256 tokensToReceive = calculatePurchaseReturn(vaporAmount);
        if (tokensToReceive == 0) revert InvalidReturn();

        vapor.safeTransferFrom(msg.sender, address(this), vaporAmount);
        token.safeTransfer(msg.sender, tokensToReceive);

        tokensSold += tokensToReceive;
        vaporCollected += vaporAmount;

        if (vaporCollected >= targetVapor) {
            tradingActive = false;
        }

        emit TokensPurchased(msg.sender, tokensToReceive, vaporAmount);
    }

    function sellTokens(uint256 tokenAmount) external nonReentrant {
        if (tokenAmount == 0) revert InvalidAmount();
        if (!tradingActive) revert TradingStopped();
        if (hasGraduated) revert AlreadyGraduated();

        uint256 vaporToReceive = calculateSaleReturn(tokenAmount);
        if (vaporToReceive == 0) revert InvalidReturn();
        if (vapor.balanceOf(address(this)) < vaporToReceive) revert InsufficientVAPOR();

        token.safeTransferFrom(msg.sender, address(this), tokenAmount);
        vapor.safeTransfer(msg.sender, vaporToReceive);

        tokensSold -= tokenAmount;
        vaporCollected -= vaporToReceive;

        emit TokensSold(msg.sender, tokenAmount, vaporToReceive);
    }

    function graduate() external nonReentrant {
        if (hasGraduated) revert AlreadyGraduated();
        if (vaporCollected < targetVapor) revert NotReadyToGraduate();

        // Stop trading
        tradingActive = false;
        hasGraduated = true;

        // Get the reserve tokens from the token contract
        address reserveAddress = Token(address(token)).reserve();
        uint256 reserveTokens = token.balanceOf(reserveAddress);

        // Create the liquidity pool with all collected VAPOR and reserve tokens
        vapor.approve(address(liquidityPool), vaporCollected);
        token.approve(address(liquidityPool), reserveTokens);
        liquidityPool.createPool(address(token), address(vapor), reserveTokens, vaporCollected);

        emit CurveGraduated(reserveTokens, vaporCollected);
    }

    function calculatePurchaseReturn(uint256 vaporAmount) public view returns (uint256) {
        if (!tradingActive) revert TradingStopped();
        if (hasGraduated) revert AlreadyGraduated();
        uint256 currentPrice = getCurrentPrice();
        return (vaporAmount * PRECISION) / currentPrice;
    }

    function calculateSaleReturn(uint256 tokenAmount) public view returns (uint256) {
        if (!tradingActive) revert TradingStopped();
        if (hasGraduated) revert AlreadyGraduated();
        uint256 currentPrice = getCurrentPrice();
        return (tokenAmount * currentPrice) / PRECISION;
    }
}
