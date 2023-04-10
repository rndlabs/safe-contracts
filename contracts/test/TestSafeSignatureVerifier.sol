// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

import "../handler/SignatureVerifierMuxer.sol";

/**
 * @title TestSafeSignatureVerifier - A simple test contract that implements the ISafeSignatureVerifier interface
 */
contract TestSafeSignatureVerifier is ISafeSignatureVerifier {
    /**
     * Validates a signature for a Safe.
     * @param hash of the message to verify
     * @param signature implementation specific signature
     */
    function isValidSafeSignature(Safe, address, bytes32 hash, bytes calldata signature)
        external
        pure
        returns (bytes4 magic)
    {
        if (hash == keccak256(signature)) {
            return 0x1626ba7e;
        }
    }

}
