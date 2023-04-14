// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

import "./extensible/FallbackHandler.sol";
import "./extensible/SignatureVerifierMuxer.sol";
import "./extensible/TokenCallbacks.sol";
import "./extensible/IERC165Handler.sol";

/**
 * @title ExtensibleFallbackHandler - A fully extensible fallback handler for Safes
 * @dev Designed to be used with Safe >= 1.3.0.
 * @author mfw78 <mfw78@rndlabs.xyz>
 */
contract ExtensibleFallbackHandler is FallbackHandler, SignatureVerifierMuxer, TokenCallbacks, IERC165Handler {
    string public constant NAME = "Extensible Fallback Handler";
    string public constant VERSION = "1.0.0";

    /**
     * Specify specific interfaces (ERC721 + ERC1155) that this contract supports.
     * @param interfaceId The interface ID to check for support
     */
    function _supportsInterface(bytes4 interfaceId) internal pure override returns (bool) {
        return interfaceId == type(ERC721TokenReceiver).interfaceId
            || interfaceId == type(ERC1155TokenReceiver).interfaceId;
    }
}
