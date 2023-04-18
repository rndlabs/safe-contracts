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
        data = bytes32(uint256(uint160(handler)) | (isStatic ? 0 : (1 << 248)));
    }

    function encodeWithSelector(bool isStatic, bytes4 selector, address handler) internal pure returns (bytes32 data) {
        data = bytes32(uint256(uint160(handler)) | (isStatic ? 0 << 248 : 1) | (uint256(uint32(selector)) << 216));
    }

    /**
     * Given a `bytes32` value, decode it into a method handler and return it
     * @param data The packed data to decode
     * @return isStatic Whether the method is static (`view`) or not
     * @return handler The address of the handler contract implementing the `IFallbackMethod` or `IStaticFallbackMethod` interface
     */
    function decode(bytes32 data) internal pure returns (bool isStatic, address handler) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // set isStatic to true if the left-most byte of the data is not 0x00
            isStatic := iszero(shr(248, data))
            handler := shr(96, shl(96, data))
        }
    }

    function decodeWithSelector(bytes32 data) internal pure returns (bool isStatic, bytes4 selector, address handler) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // set isStatic to true if the left-most byte of the data is not 0x00
            isStatic := iszero(shr(248, data))
            handler := shr(96, shl(96, data))
            selector := shl(168, shr(160, data))
        }
    }
}
