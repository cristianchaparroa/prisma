// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

library TestConstants {
    /// @dev sqrtPriceX96 for 1:1 price ratio
    uint160 public constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    /// @dev Common fee tiers
    uint24 constant FEE_LOW = 500; // 0.05%
    uint24 constant FEE_MEDIUM = 3000; // 0.3%
    uint24 constant FEE_HIGH = 10000; // 1%

    /// @dev Common constants
    bytes constant ZERO_BYTES = new bytes(0);
    address constant ADDRESS_ZERO = address(0);
}
