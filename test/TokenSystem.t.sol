// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Token.sol";
import "../src/BondingCurve.sol";
import "../src/TokenFactory.sol";
import "../src/MockLiquidityPool.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VaporToken is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    function mint(address to, uint256 amount) public {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");

        _balances[from] -= amount;
        _balances[to] += amount;
        _allowances[from][msg.sender] -= amount;

        emit Transfer(from, to, amount);
        return true;
    }
}

contract TokenSystemTest is Test {
    TokenFactory public factory;
    VaporToken public vapor;
    MockLiquidityPool public liquidityPool;
    address public alice = address(0x1);
    address public bob = address(0x2);
    uint256 public constant START_PRICE = 0.0001 ether; // 0.0001 VAPOR per token
    uint256 public constant TARGET_VAPOR = 100 ether; // 100 VAPOR to complete curve

    function setUp() public {
        // Deploy VAPOR and mint some to users
        vapor = new VaporToken();
        vapor.mint(alice, 1000 ether);
        vapor.mint(bob, 1000 ether);

        // Deploy liquidity pool
        liquidityPool = new MockLiquidityPool();

        // Deploy factory
        factory = new TokenFactory(address(vapor), address(liquidityPool), START_PRICE, TARGET_VAPOR);
    }

    function testTokenCreation() public {
        vm.startPrank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");

        Token token = Token(tokenAddr);
        BondingCurve curve = BondingCurve(curveAddr);

        // Check token properties
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TEST");
        assertEq(token.totalSupply(), 1_000_000_000 * 1e18);

        // Check distribution
        uint256 curveAmount = (token.totalSupply() * 75) / 100;
        uint256 reserveAmount = token.totalSupply() - curveAmount;

        assertEq(token.balanceOf(curveAddr), curveAmount);
        assertEq(token.balanceOf(address(liquidityPool)), reserveAmount);
        assertEq(token.balanceOf(alice), 0); // Creator gets 0 tokens initially
        assertEq(token.owner(), alice); // But creator owns the contract

        // Check curve properties
        assertTrue(curve.tradingActive());
        assertEq(address(curve.token()), tokenAddr);
        assertEq(address(curve.vapor()), address(vapor));
        assertEq(curve.startPrice(), START_PRICE);
        assertEq(curve.targetVapor(), TARGET_VAPOR);
        vm.stopPrank();
    }

    function testGraduation() public {
        // Create token
        vm.startPrank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);
        Token token = Token(tokenAddr);

        // Bob buys enough tokens to reach target
        vm.startPrank(bob);
        vapor.approve(curveAddr, TARGET_VAPOR);
        curve.buyTokens(TARGET_VAPOR);

        // Verify trading is stopped
        assertFalse(curve.tradingActive());

        // Calculate expected reserve tokens (25% of total supply)
        uint256 reserveTokens = (token.totalSupply() * 25) / 100;

        // Approve reserve tokens for liquidity pool
        vm.startPrank(address(liquidityPool));
        token.approve(address(liquidityPool), reserveTokens);
        vm.stopPrank();

        // Approve token transfer from reserve
        vm.startPrank(token.reserve());
        token.approve(address(liquidityPool), reserveTokens);
        vm.stopPrank();

        // Graduate the curve
        vm.startPrank(bob);
        curve.graduate();

        // Verify graduation
        assertTrue(curve.hasGraduated());
        assertEq(vapor.balanceOf(address(liquidityPool)), TARGET_VAPOR);
        assertEq(token.balanceOf(address(liquidityPool)), reserveTokens);

        vm.stopPrank();
    }

    function testFailGraduateBeforeTarget() public {
        // Create token
        vm.startPrank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);

        // Try to graduate before reaching target
        curve.graduate();
        vm.stopPrank();
    }

    function testFailGraduateTwice() public {
        // Create token
        vm.startPrank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);

        // Bob buys enough tokens to reach target
        vm.startPrank(bob);
        vapor.approve(curveAddr, TARGET_VAPOR);
        curve.buyTokens(TARGET_VAPOR);

        // Graduate once
        curve.graduate();

        // Try to graduate again
        curve.graduate();
        vm.stopPrank();
    }

    function testFailTradingAfterGraduation() public {
        // Create token
        vm.startPrank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);

        // Bob buys enough tokens to reach target
        vm.startPrank(bob);
        vapor.approve(curveAddr, TARGET_VAPOR);
        curve.buyTokens(TARGET_VAPOR);

        // Graduate
        curve.graduate();

        // Try to buy more tokens
        vapor.approve(curveAddr, 1 ether);
        curve.buyTokens(1 ether);
        vm.stopPrank();
    }

    function testBuyingTokens() public {
        // Create token
        vm.prank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);

        // Prepare to buy tokens
        vm.startPrank(bob);
        uint256 vaporAmount = 1 ether;
        uint256 expectedTokens = curve.calculatePurchaseReturn(vaporAmount);
        vapor.approve(curveAddr, vaporAmount);

        // Buy tokens
        curve.buyTokens(vaporAmount);

        // Check balances
        Token token = Token(tokenAddr);
        assertEq(token.balanceOf(bob), expectedTokens);
        assertEq(vapor.balanceOf(curveAddr), vaporAmount);
        assertEq(curve.tokensSold(), expectedTokens);
        assertEq(curve.vaporCollected(), vaporAmount);
        vm.stopPrank();
    }

    function testSellingTokens() public {
        // Create token and buy some first
        vm.prank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);
        Token token = Token(tokenAddr);

        // Bob buys tokens
        vm.startPrank(bob);
        uint256 vaporAmount = 1 ether;
        vapor.approve(curveAddr, vaporAmount);
        curve.buyTokens(vaporAmount);
        uint256 bobTokens = token.balanceOf(bob);

        // Bob sells half his tokens
        uint256 sellAmount = bobTokens / 2;
        token.approve(curveAddr, sellAmount);
        uint256 expectedVapor = curve.calculateSaleReturn(sellAmount);
        curve.sellTokens(sellAmount);

        // Check balances
        assertEq(token.balanceOf(bob), bobTokens - sellAmount);
        assertEq(vapor.balanceOf(bob), 1000 ether - vaporAmount + expectedVapor);
        assertEq(curve.tokensSold(), bobTokens - sellAmount);
        assertEq(curve.vaporCollected(), vaporAmount - expectedVapor);
        vm.stopPrank();
    }

    function testTradingStopsAtTarget() public {
        // Create token
        vm.prank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);

        // Buy tokens until target is reached
        vm.startPrank(bob);
        vapor.approve(curveAddr, TARGET_VAPOR);
        curve.buyTokens(TARGET_VAPOR);

        // Verify trading is stopped
        assertFalse(curve.tradingActive());

        // Try to buy more (should fail)
        vm.expectRevert(abi.encodeWithSignature("TradingStopped()"));
        curve.buyTokens(1 ether);
        vm.stopPrank();
    }

    function testPriceIncreases() public {
        // Create token
        vm.prank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);

        // Record initial price
        uint256 initialPrice = curve.getCurrentPrice();

        // Buy some tokens
        vm.startPrank(bob);
        vapor.approve(curveAddr, 1 ether);
        curve.buyTokens(1 ether);

        // Verify price increased
        uint256 newPrice = curve.getCurrentPrice();
        assertGt(newPrice, initialPrice);
        vm.stopPrank();
    }

    // Failure Cases

    function testFailBuyWithoutApproval() public {
        // Create token
        vm.prank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);

        // Try to buy without approving VAPOR
        vm.startPrank(bob);
        curve.buyTokens(1 ether);
        vm.stopPrank();
    }

    function testFailBuyWithInsufficientVAPOR() public {
        // Create token
        vm.prank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);

        // Try to buy with more VAPOR than owned
        vm.startPrank(bob);
        vapor.approve(curveAddr, 2000 ether);
        curve.buyTokens(2000 ether); // Bob only has 1000 VAPOR
        vm.stopPrank();
    }

    function testFailSellWithoutApproval() public {
        // Create token and buy some first
        vm.prank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);
        Token token = Token(tokenAddr);

        // Bob buys tokens
        vm.startPrank(bob);
        vapor.approve(curveAddr, 1 ether);
        curve.buyTokens(1 ether);
        uint256 bobTokens = token.balanceOf(bob);

        // Try to sell without approving tokens
        curve.sellTokens(bobTokens);
        vm.stopPrank();
    }

    function testFailSellMoreThanOwned() public {
        // Create token and buy some first
        vm.prank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);
        Token token = Token(tokenAddr);

        // Bob buys tokens
        vm.startPrank(bob);
        vapor.approve(curveAddr, 1 ether);
        curve.buyTokens(1 ether);
        uint256 bobTokens = token.balanceOf(bob);

        // Try to sell more than owned
        token.approve(curveAddr, bobTokens * 2);
        curve.sellTokens(bobTokens * 2);
        vm.stopPrank();
    }

    function testFailFactoryInitializationWithZeroAddress() public {
        factory = new TokenFactory(address(0), address(liquidityPool), START_PRICE, TARGET_VAPOR);
    }

    function testFailFactoryInitializationWithZeroPrice() public {
        factory = new TokenFactory(address(vapor), address(liquidityPool), 0, TARGET_VAPOR);
    }

    function testFailUpdateParametersWithZeroValues() public {
        vm.startPrank(alice);
        vm.expectRevert("Invalid start price");
        factory.updateDefaultParameters(0, TARGET_VAPOR);

        factory.updateDefaultParameters(START_PRICE, 0);
        vm.stopPrank();
    }

    function testFailBuyZeroTokens() public {
        // Create token
        vm.prank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);

        // Try to buy zero tokens
        vm.startPrank(bob);
        curve.buyTokens(0);
        vm.stopPrank();
    }

    function testFailSellZeroTokens() public {
        // Create token
        vm.prank(alice);
        (address tokenAddr, address curveAddr) = factory.createToken("Test Token", "TEST");
        BondingCurve curve = BondingCurve(curveAddr);

        // Try to sell zero tokens
        vm.startPrank(bob);
        curve.sellTokens(0);
        vm.stopPrank();
    }
}
