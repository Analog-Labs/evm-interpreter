// SPDX-License-Identifier: MIT
/*
 * This this an subset of the original BranchlessMath implemented by Lohann Paterno Coutinho Ferreira, which is released under MIT.
 * original: https://github.com/Analog-Labs/analog-gmp/blob/main/src/utils/BranchlessMath.sol
 */

pragma solidity >=0.7.0 <0.9.0;

/**
 * @dev Utilities for branchless operations, useful when a constant gas cost is required.
 */
library BranchlessMath {

    /**
     * @dev Cast a boolean (false or true) to a uint256 (0 or 1) with no jump.
     */
    function toUint(bool b) internal pure returns (uint256 u) {
        assembly {
            u := iszero(iszero(b))
        }
    }

    /**
     * @dev Return the log in base 2 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log2(uint256 x) internal pure returns (uint256 r) {
        unchecked {
            // Round down to the closest power of 2
            // Reference: https://graphics.stanford.edu/~seander/bithacks.html#RoundUpPowerOf2
            x |= x >> 1;
            x |= x >> 2;
            x |= x >> 4;
            x |= x >> 8;
            x |= x >> 16;
            x |= x >> 32;
            x |= x >> 64;
            x |= x >> 128;
            x = (x >> 1) + 1;

            assembly {
                r := byte(mod(mod(x, 255), 11), 0x010002040007030605000000000000000000000000000000000000000000)
                r := add(shr(248, mul(shr(r, x), 0x08101820283038404850586068707880889098a0a8b0b8c0c8d0d8e0e8f0f8)), r)
            }
        }
    }

    /**
     * @dev Count the consecutive zero bits (trailing) on the right.
     */
    function leadingZeros(uint256 x) internal pure returns (uint256 r) {
        return 255 - log2(x) + toUint(x == 0);
    }
}