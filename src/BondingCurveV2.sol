// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./MockLiquidityPool.sol";
import "./Token.sol";

/**
 * @title BondingCurveV2
 * @dev Enhanced version of BondingCurve with improved price calculations and safety features
 */
contract BondingCurveV2 is ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    IERC20 public immutable vapor;
    MockLiquidityPool public immutable liquidityPool;

    uint256 public immutable startPrice;
    uint256 public immutable targetVapor;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MIN_PURCHASE = 1e15; // Minimum purchase amount to prevent dust

    // Curve parameters
    uint256 public constant EXPONENT = 2; // Quadratic curve
    uint256 public tokensSold;
    uint256 public vaporCollected;
    bool public hasGraduated;

    // Events
    event TokensPurchased(address indexed buyer, uint256 tokenAmount, uint256 vaporAmount);
    event TokensSold(address indexed seller, uint256 tokenAmount, uint256 vaporAmount);
    event CurveGraduated(uint256 tokenAmount, uint256 vaporAmount);
    event PriceUpdate(uint256 newPrice);

    // Custom errors
    error InvalidAmount();
    error TradingStopped();
    error InvalidReturn();
    error InsufficientVAPOR();
    error AlreadyGraduated();
    error NotReadyToGraduate();
    error BelowMinimumPurchase();
    error PriceCalculationError();
    error TransferFailed();

    constructor(
        address _token,
        address _vapor,
        address _liquidityPool,
        uint256 _startPrice,
        uint256 _targetVapor
    ) {
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

    /**
     * @dev Calculates the current price using a more precise mathematical formula
     * Implements overflow protection and handles edge cases
     */
    function getCurrentPrice() public view returns (uint256) {
        uint256 remainingSupply = token.balanceOf(address(this)) - tokensSold;
        uint256 totalSupply = token.balanceOf(address(this));
        
        if (totalSupply == 0) revert PriceCalculationError();
        if (remainingSupply > totalSupply) revert PriceCalculationError();

        // Use a more precise calculation method
        uint256 soldRatio = ((totalSupply - remainingSupply) * PRECISION) / totalSupply;
        
        // Calculate price increase factor with overflow protection
        uint256 priceIncreaseFactor;
        unchecked {
            // Safe because EXPONENT is constant 2
            priceIncreaseFactor = PRECISION + (EXPONENT * soldRatio);
        }

        // Calculate final price with overflow protection
        return (startPrice * priceIncreaseFactor) / PRECISION;
    }

    /**
     * @dev Enhanced token purchase function with additional safety checks
     */
    function buyTokens(uint256 vaporAmount) external nonReentrant whenNotPaused {
        if (vaporAmount < MIN_PURCHASE) revert BelowMinimumPurchase();
        if (hasGraduated) revert AlreadyGraduated();
        if (vaporAmount == 0) revert InvalidAmount();

        uint256 tokensToReceive = calculatePurchaseReturn(vaporAmount);
        if (tokensToReceive == 0) revert InvalidReturn();

        // Check if purchase would exceed targetVapor
        if (vaporCollected + vaporAmount > targetVapor) {
            uint256 allowedAmount = targetVapor - vaporCollected;
            tokensToReceive = calculatePurchaseReturn(allowedAmount);
            vaporAmount = allowedAmount;
        }

        // Execute the trade
        vapor.safeTransferFrom(msg.sender, address(this), vaporAmount);
        token.safeTransfer(msg.sender, tokensToReceive);

        tokensSold += tokensToReceive;
        vaporCollected += vaporAmount;

        emit TokensPurchased(msg.sender, tokensToReceive, vaporAmount);
        emit PriceUpdate(getCurrentPrice());

        // Check graduation condition
        if (vaporCollected >= targetVapor) {
            _pause();
        }
    }

    /**
     * @dev Enhanced token sale function with additional safety checks
     */
    function sellTokens(uint256 tokenAmount) external nonReentrant whenNotPaused {
        if (tokenAmount == 0) revert InvalidAmount();
        if (hasGraduated) revert AlreadyGraduated();

        uint256 vaporToReceive = calculateSaleReturn(tokenAmount);
        if (vaporToReceive == 0) revert InvalidReturn();
        if (vaporToReceive > vapor.balanceOf(address(this))) revert InsufficientVAPOR();

        // Execute the trade
        token.safeTransferFrom(msg.sender, address(this), tokenAmount);
        vapor.safeTransfer(msg.sender, vaporToReceive);

        tokensSold -= tokenAmount;
        vaporCollected -= vaporToReceive;

        emit TokensSold(msg.sender, tokenAmount, vaporToReceive);
        emit PriceUpdate(getCurrentPrice());
    }

    /**
     * @dev Enhanced graduation function with additional safety checks
     */
    function graduate() external nonReentrant {
        if (hasGraduated) revert AlreadyGraduated();
        if (vaporCollected < targetVapor) revert NotReadyToGraduate();

        // Stop trading
        _pause();
        hasGraduated = true;

        // Get the reserve tokens
        address reserveAddress = Token(address(token)).reserve();
        uint256 reserveTokens = token.balanceOf(reserveAddress);

        // Update token state
        Token(address(token)).setGraduated();

        // Create liquidity pool
        vapor.approve(address(liquidityPool), vaporCollected);
        token.approve(address(liquidityPool), reserveTokens);
        
        try liquidityPool.createPool(
            address(token),
            address(vapor),
            reserveTokens,
            vaporCollected
        ) {
            emit CurveGraduated(reserveTokens, vaporCollected);
        } catch {
            revert TransferFailed();
        }
    }

    /**
     * @dev Calculate purchase return with improved precision
     */
    function calculatePurchaseReturn(uint256 vaporAmount) public view returns (uint256) {
        if (hasGraduated) revert AlreadyGraduated();
        if (whenNotPaused()) revert TradingStopped();
        
        uint256 currentPrice = getCurrentPrice();
        if (currentPrice == 0) revert PriceCalculationError();
        
        return (vaporAmount * PRECISION) / currentPrice;
    }

    /**
     * @dev Calculate sale return with improved precision
     */
    function calculateSaleReturn(uint256 tokenAmount) public view returns (uint256) {
        if (hasGraduated) revert AlreadyGraduated();
        if (whenNotPaused()) revert TradingStopped();
        
        uint256 currentPrice = getCurrentPrice();
        return (tokenAmount * currentPrice) / PRECISION;
    }
}