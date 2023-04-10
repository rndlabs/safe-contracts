// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

import "./ExtensibleFallbackHandler.sol";

interface ERC1271 {
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue);
}

interface ISafeSignatureVerifier {
    function isValidSafeSignature(Safe safe, address sender, bytes32 hash, bytes calldata signature)
        external
        returns (bytes4 magic);
}

/**
 * @title ERC-1271 Signature Verifier Multiplexer
 * @notice This contract is designed for use with the `ExtensibleFallbackHandler`, implementing `IFallbackMethod`
 *         for the `isValidSignature(bytes32,bytes)` method of ERC-1271.
 * @dev This contract only implements the `isValidSignature(bytes32,bytes)` method of ERC-1271, and does not support
 *      the legacy `isValidSignature(bytes,bytes)` method.
 * @author mfw78 <mfw78@rndlabs.xyz>
 */
contract SignatureVerifierMuxer is IFallbackMethod {
    // keccak256("SafeMessage(bytes message)");
    bytes32 private constant SAFE_MSG_TYPEHASH = 0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca;

    // Mapping to keep track of safe-specific domain verifiers
    mapping(Safe => mapping(bytes32 => ISafeSignatureVerifier)) public domainVerifiers;

    event AddedDomainVerifier(Safe indexed safe, bytes32 domainSeparator, ISafeSignatureVerifier verifier);
    event ChangedDomainVerifier(
        Safe indexed safe,
        bytes32 domainSeparator,
        ISafeSignatureVerifier oldVerifier,
        ISafeSignatureVerifier newVerifier
    );
    event RemovedDomainVerifier(Safe indexed safe, bytes32 domainSeparator);

    /**
     * Setter for a safe-specific domain verifier
     * @param domainSeparator The domain separator of the ISafeSignatureVerifier
     * @param newVerifier A contract that implements the ISafeSignatureVerifier interface
     */
    function setDomainVerifier(bytes32 domainSeparator, ISafeSignatureVerifier newVerifier) external {
        Safe safe = Safe(payable(msg.sender));
        ISafeSignatureVerifier oldVerifier = domainVerifiers[safe][domainSeparator];
        if (address(newVerifier) == address(0) && address(oldVerifier) != address(0)) {
            delete domainVerifiers[safe][domainSeparator];
            emit RemovedDomainVerifier(safe, domainSeparator);
        } else {
            domainVerifiers[safe][domainSeparator] = newVerifier;
            if (address(oldVerifier) == address(0)) {
                emit AddedDomainVerifier(safe, domainSeparator, newVerifier);
            } else {
                emit ChangedDomainVerifier(safe, domainSeparator, oldVerifier, newVerifier);
            }
        }
    }

    /**
     * @dev Handle an ERC-1271 `isValidSignature(bytes32,bytes)` method call.
     * @param safe Address of the Safe that is calling this method
     * @param sender Address that is calling the Safe
     * @param data Raw calldata that was sent associated with the selector
     */
    function handle(Safe safe, address sender, bytes calldata data) external override returns (bytes memory) {
        // Raw calldata is wrapped in `data`. Check that it is `isValidSignature(bytes32,bytes)`.
        bytes4 selector;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            selector := shl(224, shr(224, calldataload(data.offset)))
        }
        require(selector == ERC1271.isValidSignature.selector, "Invalid selector");

        // Get the parameters, skipping the first 4bytes as that is the non-padded selector.
        (bytes32 message, bytes memory signature) = abi.decode(data[4:], (bytes32, bytes));

        // Fetch the last 32 bytes to see if it is a verifier for the `domainSeparator`.
        // We don't have to worry about the length of `data` at this point as the previous decode will have fail if it was too short.
        bytes32 domain = abi.decode(data[data.length - 32:], (bytes32));

        bytes4 magic;
        ISafeSignatureVerifier verifier = domainVerifiers[safe][domain];
        // If the domain doesn't exist, ie. `address(0)`, then do the default processing.
        if (address(verifier) == address(0)) {
            magic = defaultIsValidSafeSignature(safe, message, signature);
        } else {
            // Preserving the context, we call an `ISafeSignatureVerifier` who is authorised to sign for this safe.
            magic = verifier.isValidSafeSignature(safe, sender, message, signature);
        }

        // use `abi.encode` to return a full evm word as that's what's expected by solidity.
        bytes memory returnData = abi.encode(magic);

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Skip the first 32 bytes which contains `abi.encode` length of bytes and return
            return(add(returnData, 0x20), mload(returnData))
        }
    }

    /**
     * @dev Default behaviour of `isValidSignature(bytes32,bytes)` for a Safe.
     * @param safe The safe to verify the signature for
     * @param message A message hash to verify
     * @param signature The owner's signature, or empty bytes if `signedMessages`
     * @return magic ERC1271.isValidSignature.selector magic value or reverts
     */
    function defaultIsValidSafeSignature(Safe safe, bytes32 message, bytes memory signature)
        internal
        view
        returns (bytes4 magic)
    {
        bytes memory messageData = encodeMessageDataForSafe(safe, abi.encode(message));
        bytes32 messageHash = keccak256(messageData);
        if (signature.length == 0) {
            require(safe.signedMessages(messageHash) != 0, "Hash not approved");
        } else {
            safe.checkSignatures(messageHash, messageData, signature);
        }
        return ERC1271.isValidSignature.selector;
    }

    /**
     * @dev Returns the pre-image of the message hash (see getMessageHashForSafe).
     * @param safe Safe to which the message is targeted.
     * @param message Message that should be encoded.
     * @return Encoded message.
     */
    function encodeMessageDataForSafe(Safe safe, bytes memory message) internal view returns (bytes memory) {
        bytes32 safeMessageHash = keccak256(abi.encode(SAFE_MSG_TYPEHASH, keccak256(message)));
        return abi.encodePacked(bytes1(0x19), bytes1(0x01), safe.domainSeparator(), safeMessageHash);
    }
}
