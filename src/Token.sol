// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Token is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18; // 1 billion tokens with 18 decimals
    uint256 public constant CURVE_SHARE = 75; // 75% to bonding curve
    uint256 public constant RESERVE_SHARE = 25; // 25% reserved for liquidity pool

    address public immutable reserve; // Address where reserve tokens are held

    constructor(string memory name, string memory symbol, address creator, address _reserve)
        ERC20(name, symbol)
        Ownable(creator)
    {
        require(_reserve != address(0), "Invalid reserve address");
        reserve = _reserve;

        // Mint tokens to factory (to be distributed to curve) and reserve
        _mint(msg.sender, TOTAL_SUPPLY * CURVE_SHARE / 100); // Factory gets curve's share
        _mint(_reserve, TOTAL_SUPPLY * RESERVE_SHARE / 100); // Reserve gets its share
    }
}
