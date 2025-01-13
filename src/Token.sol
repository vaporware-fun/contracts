// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Token is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18; // 1 billion tokens with 18 decimals
    uint256 public constant CURVE_SHARE = 75; // 75% to bonding curve
    uint256 public constant RESERVE_SHARE = 25; // 25% reserved for liquidity pool

    address public immutable reserve; // Address where reserve tokens are held
    address private _curve; // Address of the bonding curve
    bool public hasGraduated; // Whether the token has graduated

    error NotGraduated();
    error NotCurve();
    error CurveAlreadySet();

    constructor(string memory name, string memory symbol, address creator, address _reserve, address initialCurve)
        ERC20(name, symbol)
        Ownable(creator)
    {
        require(_reserve != address(0), "Invalid reserve address");
        require(initialCurve != address(0), "Invalid curve address");
        reserve = _reserve;
        _curve = initialCurve;

        // Mint tokens to factory (to be distributed to curve) and reserve
        _mint(msg.sender, TOTAL_SUPPLY * CURVE_SHARE / 100); // Factory gets curve's share
        _mint(_reserve, TOTAL_SUPPLY * RESERVE_SHARE / 100); // Reserve gets its share
    }

    function curve() public view returns (address) {
        return _curve;
    }

    function updateCurveAddress(address newCurve) external {
        require(msg.sender == _curve, "Only factory can set curve");
        require(newCurve != address(0), "Invalid curve address");
        require(_curve == msg.sender, "Curve already set");
        _curve = newCurve;
    }

    function setGraduated() external {
        require(msg.sender == _curve, "Only curve can graduate");
        hasGraduated = true;
    }

    function _update(address from, address to, uint256 amount) internal virtual override {
        if (!hasGraduated) {
            // Before graduation, only allow transfers:
            // 1. From curve to users (buying)
            // 2. From users to curve (selling)
            // 3. Initial distribution (from zero address)
            // 4. To curve from factory (initial setup)
            bool isInitialDistribution = from == address(0);
            bool isInitialCurveSetup = to == _curve;
            bool isCurveBuying = from == _curve;
            bool isCurveSelling = to == _curve;

            if (!isInitialDistribution && !isInitialCurveSetup && !isCurveBuying && !isCurveSelling) {
                revert NotGraduated();
            }
        }

        super._update(from, to, amount);
    }
}
