// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/BondingCurveV2.sol";
import "../src/Token.sol";
import "../src/MockLiquidityPool.sol";

contract BondingCurveV2Test is Test {
    BondingCurveV2 public curve;
    Token public token;
    MockLiquidityPool public liquidityPool;
    IERC20 public vapor;
    
    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    
    uint256 public constant INITIAL_SUPPLY = 1000000 * 1e18;
    uint256 public constant START_PRICE = 1e18;
    uint256 public constant TARGET_VAPOR = 1000 * 1e18;
    uint256 public constant MIN_PURCHASE = 1e15;
    
    event TokensPurchased(address indexed buyer, uint256 tokenAmount, uint256 vaporAmount);
    event TokensSold(address indexed seller, uint256 tokenAmount, uint256 vaporAmount);
    event CurveGraduated(uint256 tokenAmount, uint256 vaporAmount);
    event PriceUpdate(uint256 newPrice);
    
    function setUp() public {
        vm.startPrank(admin);
        vapor = new Token("VAPOR", "VAPOR", INITIAL_SUPPLY);
        token = new Token("Test Token", "TEST", INITIAL_SUPPLY);
        liquidityPool = new MockLiquidityPool();
        
        curve = new BondingCurveV2(
            address(token),
            address(vapor),
            address(liquidityPool),
            START_PRICE,
            TARGET_VAPOR
        );
        
        token.transfer(address(curve), INITIAL_SUPPLY);
        vapor.transfer(user1, 1000 * 1e18);
        vapor.transfer(user2, 1000 * 1e18);
        vm.stopPrank();
    }
    
    function testInitialState() public {
        assertEq(curve.startPrice(), START_PRICE);
        assertEq(curve.targetVapor(), TARGET_VAPOR);
        assertEq(curve.tokensSold(), 0);
        assertEq(curve.vaporCollected(), 0);
        assertFalse(curve.hasGraduated());
    }
    
    function testBuyTokens() public {
        vm.startPrank(user1);
        uint256 vaporAmount = 100 * 1e18;
        uint256 expectedTokens = curve.calculatePurchaseReturn(vaporAmount);
        
        vapor.approve(address(curve), vaporAmount);
        
        vm.expectEmit(true, true, true, true);
        emit TokensPurchased(user1, expectedTokens, vaporAmount);
        
        curve.buyTokens(vaporAmount);
        
        assertEq(curve.tokensSold(), expectedTokens);
        assertEq(curve.vaporCollected(), vaporAmount);
        assertEq(token.balanceOf(user1), expectedTokens);
        vm.stopPrank();
    }
    
    function testSellTokens() public {
        // First buy tokens
        vm.startPrank(user1);
        uint256 vaporAmount = 100 * 1e18;
        vapor.approve(address(curve), vaporAmount);
        curve.buyTokens(vaporAmount);
        uint256 tokensReceived = token.balanceOf(user1);
        
        // Then sell them
        token.approve(address(curve), tokensReceived);
        uint256 expectedVapor = curve.calculateSaleReturn(tokensReceived);
        
        vm.expectEmit(true, true, true, true);
        emit TokensSold(user1, tokensReceived, expectedVapor);
        
        curve.sellTokens(tokensReceived);
        
        assertEq(curve.tokensSold(), 0);
        assertEq(curve.vaporCollected(), 0);
        assertEq(token.balanceOf(user1), 0);
        vm.stopPrank();
    }
    
    function testGraduation() public {
        vm.startPrank(user1);
        vapor.approve(address(curve), TARGET_VAPOR);
        curve.buyTokens(TARGET_VAPOR);
        
        vm.expectEmit(true, true, true, true);
        emit CurveGraduated(token.balanceOf(token.reserve()), TARGET_VAPOR);
        
        curve.graduate();
        
        assertTrue(curve.hasGraduated());
        assertTrue(curve.paused());
        vm.stopPrank();
    }
    
    function testFailBuyBelowMinimum() public {
        vm.startPrank(user1);
        vapor.approve(address(curve), MIN_PURCHASE - 1);
        vm.expectRevert(BondingCurveV2.BelowMinimumPurchase.selector);
        curve.buyTokens(MIN_PURCHASE - 1);
        vm.stopPrank();
    }
    
    function testFailBuyAfterGraduation() public {
        vm.startPrank(user1);
        vapor.approve(address(curve), TARGET_VAPOR);
        curve.buyTokens(TARGET_VAPOR);
        curve.graduate();
        
        vm.expectRevert(BondingCurveV2.AlreadyGraduated.selector);
        curve.buyTokens(100 * 1e18);
        vm.stopPrank();
    }
    
    function testFailSellAfterGraduation() public {
        vm.startPrank(user1);
        vapor.approve(address(curve), TARGET_VAPOR);
        curve.buyTokens(TARGET_VAPOR);
        curve.graduate();
        
        vm.expectRevert(BondingCurveV2.AlreadyGraduated.selector);
        curve.sellTokens(100 * 1e18);
        vm.stopPrank();
    }
    
    function testPriceIncrease() public {
        uint256 initialPrice = curve.getCurrentPrice();
        
        vm.startPrank(user1);
        uint256 vaporAmount = 100 * 1e18;
        vapor.approve(address(curve), vaporAmount);
        curve.buyTokens(vaporAmount);
        
        uint256 newPrice = curve.getCurrentPrice();
        assertTrue(newPrice > initialPrice);
        vm.stopPrank();
    }
}