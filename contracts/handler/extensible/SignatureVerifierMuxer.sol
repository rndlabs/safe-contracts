// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

import "./Base.sol";
import "../../interfaces/ISignatureValidator.sol";

interface ERC1271 {
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue);
}

/**
 * @title Safe Signature Verifier Interface
 * @author mfw78 <mfw78@rndlabs.xyz>
 * @notice This interface provides an standard for external contracts that are verifying signatures
 *         for a Safe.
 */
interface ISafeSignatureVerifier {
    /**
     * @dev If called by `SignatureVerifierMuxer`, the following has already been checked:
     *      _hash = h(abi.encodePacked("\x19\x01", domainSeparator, h(typeHash || encodeData)));
     * @param safe The Safe that has delegated the signature verification
     * @param sender The address that originally called the Safe's `isValidSignature` method
     * @param _hash The EIP-712 hash whose signature will be verified
     * @param domainSeparator The EIP-712 domainSeparator
     * @param typeHash The EIP-712 typeHash
     * @param encodeData The EIP-712 encoded data
     * @param payload An arbitrary payload that can be used to pass additional data to the verifier
     * @return magic The magic value that should be returned if the signature is valid (0x1626ba7e)
     */
    function isValidSafeSignature(
        Safe safe,
        address sender,
        bytes32 _hash,
        bytes32 domainSeparator,
        bytes32 typeHash,
        bytes calldata encodeData,
        bytes calldata payload
    ) external view returns (bytes4 magic);
}

/**
 * @title ERC-1271 Signature Verifier Multiplexer (Muxer)
 * @author mfw78 <mfw78@rndlabs.xyz>
 * @notice Allows delegating EIP-712 domains to an arbitray `ISafeSignatureVerifier`
 * @dev This multiplexer enforces a strict authorisation per domainSeparator. This is to prevent a malicious
 *     `ISafeSignatureVerifier` from being able to verify signatures for any domainSeparator. This does not prevent
 *      an `ISafeSignatureVerifier` from being able to verify signatures for multiple domainSeparators, however
 *      each domainSeparator requires specific approval by Safe.
 */
abstract contract SignatureVerifierMuxer is ExtensibleBase, ISignatureValidator {
    // --- constants ---
    // keccak256("SafeMessage(bytes message)");
    bytes32 private constant SAFE_MSG_TYPEHASH = 0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca;
    // keccak256("safeSignature(bytes32,bytes32,bytes,bytes)");
    bytes4 private constant SAFE_SIGNATURE_MAGIC_VALUE = 0x5fd7e97d;

    // --- storage ---
    mapping(Safe => mapping(bytes32 => ISafeSignatureVerifier)) public domainVerifiers;

    // --- events ---
    event AddedDomainVerifier(Safe indexed safe, bytes32 domainSeparator, ISafeSignatureVerifier verifier);
    event ChangedDomainVerifier(
        Safe indexed safe,
        bytes32 domainSeparator,
        ISafeSignatureVerifier oldVerifier,
        ISafeSignatureVerifier newVerifier
    );
    event RemovedDomainVerifier(Safe indexed safe, bytes32 domainSeparator);

    /**
     * Setter for the signature muxer
     * @param domainSeparator The domainSeparator authorised for the `ISafeSignatureVerifier`
     * @param newVerifier A contract that implements `ISafeSignatureVerifier`
     */
    function setDomainVerifier(bytes32 domainSeparator, ISafeSignatureVerifier newVerifier) public onlySelf {
        Safe safe = Safe(payable(_msgSender()));
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
     * @notice Implements ERC1271 interface for smart contract EIP-712 signature validation
     * @dev The signature format is the same as the one used by the Safe contract
     * @param _hash Hash of the data that is signed
     * @param signature The signature to be verified
     * @return magic Standardised ERC1271 return value
     */
    function isValidSignature(bytes32 _hash, bytes calldata signature) external view returns (bytes4 magic) {
        (Safe safe, address sender) = _getContext();
        
        bytes4 sigSelector;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // For solidity v0.7.6 - extract the first 4 bytes of the signature
            // (the selector of the signature method)
            // Use calldata offset 100 bytes to skip:
            //  - 4 bytes for the method selector
            //  - 32 bytes for the _hash parameter
            //  - 64 bytes for the solidity memory pointer to the signature
            // There is no need to check the length of the calldata as the
            // `calldataload` will return 0 for any bytes that are not available.
            // If using a newer version of solidity, this can be replaced with:
            // bytes4(signature[0:4])
            sigSelector := calldataload(100)
        }

        // Check if the signature is for an `ISafeSignatureVerifier` and if it is valid for the domain.
        if (sigSelector == SAFE_SIGNATURE_MAGIC_VALUE) {
            // Get the domainSeparator from the signature.
            (bytes32 domainSeparator, bytes32 typeHash) = abi.decode(signature[4:68], (bytes32, bytes32));

            ISafeSignatureVerifier verifier = domainVerifiers[safe][domainSeparator];
            // Check if there is an `ISafeSignatureVerifier` for the domain.
            if (address(verifier) != address(0)) {
                bytes memory encodeData = SolidityTools.getNestedCallData(100, 68);
                bytes memory payload = SolidityTools.getNestedCallData(100, 100);

                // Check that the signature is valid for the domain.
                if (keccak256(EIP712.encodeMessageData(domainSeparator, typeHash, encodeData)) == _hash) {
                    // Preserving the context, call the Safe's authorised `ISafeSignatureVerifier` to verify.
                    return verifier.isValidSafeSignature(
                        safe, sender, _hash, domainSeparator, typeHash, encodeData, payload
                    );
                }
            }
        }

        // domainVerifier doesn't exist or the signature is invalid for the domain - fall back to the default
        return defaultIsValidSignature(safe, abi.encode(_hash), signature);
    }

    /**
     * @notice Legacy EIP-1271 signature validation method.
     * @dev Implementation of ISignatureValidator (see `interfaces/ISignatureValidator.sol`)
     * @param _data Arbitrary length data signed on the behalf of address(msg.sender).
     * @param _signature Signature byte array associated with _data.
     * @return a bool upon valid or invalid signature with corresponding _data.
     */
    function isValidSignature(bytes memory _data, bytes memory _signature) public view override returns (bytes4) {
        // Caller should be a Safe
        Safe safe = Safe(payable(msg.sender));
        return defaultIsValidSignature(safe, _data, _signature) == ERC1271.isValidSignature.selector
            ? EIP1271_MAGIC_VALUE
            : bytes4(0);
    }

    /**
     * Default Safe signature validation (approved hashes / threshold signatures)
     * @param safe The safe being asked to validate the signature
     * @param _hash Hash of the data that is signed
     * @param signature The signature to be verified
     */
    function defaultIsValidSignature(Safe safe, bytes memory _hash, bytes memory signature)
        internal
        view
        returns (bytes4 magic)
    {
        bytes memory messageData =
            EIP712.encodeMessageData(safe.domainSeparator(), SAFE_MSG_TYPEHASH, abi.encode(keccak256(_hash)));
        bytes32 messageHash = keccak256(messageData);
        if (signature.length == 0) {
            // approved hashes
            require(safe.signedMessages(messageHash) != 0, "Hash not approved");
        } else {
            // threshold signatures
            safe.checkSignatures(messageHash, messageData, signature);
        }
        magic = ERC1271.isValidSignature.selector;
    }
}

library SolidityTools {
    /**
     * Get the nested dynamic data from calldata.
     * @param _offset The dynamic offset of the nested calldata
     * @param _nestedOffset The offset within the nested calldata, exclusive of the selector
     */
    function getNestedCallData(uint256 _offset, uint256 _nestedOffset) internal pure returns (bytes memory data) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let ptr := calldataload(add(_offset, _nestedOffset))
            let len := add(32, calldataload(add(4, add(_offset, ptr))))
            data := mload(0x40)
            calldatacopy(data, add(add(4, _offset), ptr), len)
            mstore(0x40, add(data, len))
        }
    }
}

library EIP712 {
    function encodeMessageData(bytes32 domainSeparator, bytes32 typeHash, bytes memory message)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(bytes1(0x19), bytes1(0x01), domainSeparator, keccak256(abi.encodePacked(typeHash, message)));
    }
}
