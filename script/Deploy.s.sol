// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/TokenFactory.sol";
import "../src/MockLiquidityPool.sol";
import "../src/Token.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DeployScript is Script {
    // Default parameters
    uint256 constant START_PRICE = 0.0001 ether; // 0.0001 VAPOR per token
    uint256 constant TARGET_VAPOR = 100 ether; // 100 VAPOR to complete curve

    error DeploymentFailed(string reason);
    error InvalidChain();

    function setUp() public {}

    function run() public {
        // Check environment variables
        if (!vm.envExists("PRIVATE_KEY")) {
            revert DeploymentFailed("PRIVATE_KEY not set");
        }
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Only deploy on Hyperliquid testnet
        if (block.chainid != 998) {
            revert InvalidChain();
        }

        console.log("Starting deployment on Hyperliquid testnet...");
        console.log("Deployer address:", vm.addr(deployerPrivateKey));

        vm.startBroadcast(deployerPrivateKey);

        try this.deploy() returns (
            address vaporAddr,
            address liquidityPoolAddr,
            address factoryAddr,
            address testTokenAddr,
            address testCurveAddr
        ) {
            console.log("\nDeployment Summary:");
            console.log("------------------");
            console.log("Network: Hyperliquid Testnet");
            console.log("VAPOR Token:", vaporAddr);
            console.log("Liquidity Pool:", liquidityPoolAddr);
            console.log("Token Factory:", factoryAddr);
            if (testTokenAddr != address(0)) {
                console.log("Test Token:", testTokenAddr);
                console.log("Test Curve:", testCurveAddr);
            }
            console.log("Start Price:", START_PRICE);
            console.log("Target VAPOR:", TARGET_VAPOR);
        } catch Error(string memory reason) {
            vm.stopBroadcast();
            revert DeploymentFailed(reason);
        }

        vm.stopBroadcast();
    }

    function deploy()
        external
        returns (
            address vaporAddr,
            address liquidityPoolAddr,
            address factoryAddr,
            address testTokenAddr,
            address testCurveAddr
        )
    {
        // Deploy VAPOR token first (this will be replaced with actual VAPOR on mainnet)
        VaporToken vapor = new VaporToken();
        console.log("VAPOR token deployed at:", address(vapor));

        // Deploy liquidity pool
        MockLiquidityPool liquidityPool = new MockLiquidityPool();
        console.log("Liquidity pool deployed at:", address(liquidityPool));

        // Deploy factory
        TokenFactory factory = new TokenFactory(address(vapor), address(liquidityPool), START_PRICE, TARGET_VAPOR);
        console.log("Token factory deployed at:", address(factory));

        // Optionally create a test token
        if (vm.envBool("CREATE_TEST_TOKEN")) {
            (address token, address curve) = factory.createToken("Test Token", "TEST");
            console.log("Test token deployed at:", token);
            console.log("Test token curve deployed at:", curve);
            testTokenAddr = token;
            testCurveAddr = curve;
        }

        return (address(vapor), address(liquidityPool), address(factory), testTokenAddr, testCurveAddr);
    }
}

// VAPOR token for Hyperliquid testnet
contract VaporToken {
    string public constant name = "VAPOR";
    string public constant symbol = "VAPOR";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    uint256 public constant MINT_AMOUNT = 1000 ether; // 1000 VAPOR per mint

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Minted(address indexed to, uint256 amount);

    constructor() {
        // Mint initial supply to deployer
        uint256 initialSupply = 1_000_000 * 1e18; // 1 million VAPOR
        balanceOf[msg.sender] = initialSupply;
        totalSupply = initialSupply;
        emit Transfer(address(0), msg.sender, initialSupply);
    }

    function mint() external {
        balanceOf[msg.sender] += MINT_AMOUNT;
        totalSupply += MINT_AMOUNT;
        emit Transfer(address(0), msg.sender, MINT_AMOUNT);
        emit Minted(msg.sender, MINT_AMOUNT);
    }

    // Mint a specific amount (for testing different scenarios)
    function mintAmount(uint256 amount) external {
        balanceOf[msg.sender] += amount;
        totalSupply += amount;
        emit Transfer(address(0), msg.sender, amount);
        emit Minted(msg.sender, amount);
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        return transferFrom(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");

        if (from != msg.sender && allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
            allowance[from][msg.sender] -= amount;
        }

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);

        return true;
    }
}
