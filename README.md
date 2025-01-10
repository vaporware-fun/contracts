# Vapor DEX - Bonding Curve Token Factory

A bonding curve-based token factory where users can create new ERC20 tokens with an exponential bonding curve trading against VAPOR.

## Overview

This project implements a token factory system with the following features:

- Create new ERC20 tokens with custom name and symbol
- Automatic bonding curve setup with 75% of tokens
- 25% token reserve for future liquidity pool
- Exponential pricing model
- Graduation mechanism to transition to liquidity pool

## Getting Started

### Getting Testnet VAPOR

The testnet VAPOR token contract includes a faucet functionality:

```solidity
// Get 1000 VAPOR
vaporToken.mint();

// Or get a specific amount
vaporToken.mintAmount(5000 ether); // Get 5000 VAPOR
```

There are no limits on minting as this is for testing purposes only.

## Contract Architecture

- `Token.sol`: ERC20 token implementation with initial distribution logic
- `BondingCurve.sol`: Manages token trading with exponential pricing
- `TokenFactory.sol`: Creates new tokens and their bonding curves
- `MockLiquidityPool.sol`: Simulates liquidity pool for graduated tokens

## Development

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/) (for deployment scripts)

### Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/vapor-dex.git
cd vapor-dex

# Install dependencies
forge install
```

### Testing

```bash
# Run all tests
forge test

# Run tests with verbosity
forge test -vv

# Run specific test
forge test --match-test testTokenCreation -vv
```

## Deployment

### Hyperliquid Testnet

The contracts can be deployed to the Hyperliquid testnet using the provided deployment script.

1. Set up environment variables:
```bash
export PRIVATE_KEY=your_private_key
export CREATE_TEST_TOKEN=true  # Optional: creates a test token on deployment
```

2. Deploy to Hyperliquid testnet:
```bash
forge script script/Deploy.s.sol --rpc-url https://api.hyperliquid-testnet.xyz/evm --broadcast
```

Network Details:
- Chain ID: 998
- RPC URL: https://api.hyperliquid-testnet.xyz/evm
- Currency: HYPE (for gas)

### Contract Interaction

1. Create a new token:
```solidity
// Through TokenFactory
factory.createToken("My Token", "MTK");
```

2. Buy tokens through bonding curve:
```solidity
// Approve VAPOR spending
vapor.approve(curveAddress, amount);
// Buy tokens
curve.buyTokens(amount);
```

3. Sell tokens back to curve:
```solidity
// Approve token spending
token.approve(curveAddress, amount);
// Sell tokens
curve.sellTokens(amount);
```

4. Graduate to liquidity pool:
```solidity
// Once target VAPOR is reached
curve.graduate();
```

## Parameters

- Initial token supply: 1 billion tokens
- Distribution: 75% to bonding curve, 25% to reserve
- Curve type: Exponential (quadratic)
- Default start price: 0.0001 VAPOR
- Target VAPOR: 100 VAPOR

## Security Considerations

- All contracts use OpenZeppelin's SafeERC20 for token transfers
- ReentrancyGuard protection on critical functions
- Ownership management for token contracts
- Trading state management to prevent post-graduation trading

## License

MIT
