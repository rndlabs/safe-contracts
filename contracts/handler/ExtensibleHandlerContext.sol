// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

/**
 * @title Extensible Handler Context - Allows the fallback handler to extract additional context from the calldata
 * @dev The fallback manager appends the following context to the calldata (from left to right):
 *      1. The fallback manager address (non-padded) (ie. the Safe proxy address)
 *      2. Fallback manager caller address (non-padded) (ie. the `msg.sender` of the Safe proxy transaction)
 *      Based on HandlerContext.sol.
 * @author Richard Meissner - @rmeissner
 * @author mfw78 <mfw78@rndlabs.xyz>
 */
abstract contract ExtensibleHandlerContext {
    /**
     * @notice Allows fetching the original caller address.
     * @dev This is only reliable in combination with a `FallbackManager` that supports this (e.g. Safe contract >=1.3.0)
     *      and/or `ExtensibleFallbackHandler`.
     *      When using this functionality make sure that the linked _manager (aka msg.sender) supports this.
     *      This function does not rely on a trusted forwarder. Use the returned value only to
     *      check information against the calling manager.
     * @return sender Original caller address.
     */
    function _msgSender() internal pure returns (address sender) {
        require(msg.data.length >= 40);
        // The assembly code is more direct than the Solidity version using `abi.decode`.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sender := shr(96, calldataload(sub(calldatasize(), 20)))
        }
    }

    /**
     * @notice Allows fetching the original manager address.
     * @dev This is only reliable in combination with `ExtensibleFallbackManager` that supports this.
     * @return manager Original fallback manager address.
     */
    function _manager() internal pure returns (address manager) {
        require(msg.data.length >= 40);
        // solhint-disable-next-line no-inline-assembly
        assembly {
            manager := shr(96, calldataload(sub(calldatasize(), 40)))
        }
    }
}
