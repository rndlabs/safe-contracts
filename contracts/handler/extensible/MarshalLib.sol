// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

library MarshalLib {
    /**
     * Encode a method handler into a `bytes32` value
     * @dev The first byte of the `bytes32` value is set to 0x01 if the method is not static (`view`)
     * @dev The last 20 bytes of the `bytes32` value are set to the address of the handler contract
     * @param isStatic Whether the method is static (`view`) or not
     * @param handler The address of the handler contract implementing the `IFallbackMethod` or `IStaticFallbackMethod` interface
     */
    function encode(bool isStatic, address handler) internal pure returns (bytes32 data) {
        // use assembly to set the first (leftmost) byte of the data to 0x01 if the method is not static
        assembly {
            // shift the data to the right by 12 bytes (96 bits)
            data := handler
            if iszero(isStatic) {
                // set the left-most byte of the data to 0x01
                data := or(data, 0x0100000000000000000000000000000000000000000000000000000000000000)
            }
        }
    }

    function encodeWithSelector(bool isStatic, bytes4 selector, address handler) internal pure returns (bytes32 data) {
        assembly {
            // shift the data to the right by 12 bytes (96 bits)
            data := handler
            if iszero(isStatic) {
                // set the left-most byte of the data to 0x01
                data := or(data, 0x0100000000000000000000000000000000000000000000000000000000000000)
            }

            // set the 4 bytes between the left-most byte + 1 and left-most byte + 5 to the selector
            data := or(data, shr(8, selector))
        }
    }

    /**
     * Given a `bytes32` value, decode it into a method handler and return it
     * @param data The packed data to decode
     * @return isStatic Whether the method is static (`view`) or not
     * @return handler The address of the handler contract implementing the `IFallbackMethod` or `IStaticFallbackMethod` interface
     */
    function decode(bytes32 data) internal pure returns (bool isStatic, address handler) {
        assembly {
            // set isStatic to true if the left-most byte of the data is not 0x00
            isStatic := iszero(shr(248, data))
            handler := shr(96, shl(96, data))
        }
    }

    function decodeWithSelector(bytes32 data) internal pure returns (bool isStatic, bytes4 selector, address handler) {
        assembly {
            // set isStatic to true if the left-most byte of the data is not 0x00
            isStatic := iszero(shr(248, data))
            handler := shr(96, shl(96, data))
            selector := shl(168, shr(160, data))
        }
    }
}
