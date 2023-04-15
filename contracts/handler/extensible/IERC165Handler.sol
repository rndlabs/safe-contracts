// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

import {IERC165} from "../../interfaces/IERC165.sol";

import "./Base.sol";

abstract contract IERC165Handler is ExtensibleBase {
    // --- events ---

    event AddedInterface(Safe indexed safe, bytes4 interfaceId);
    event RemovedInterface(Safe indexed safe, bytes4 interfaceId);

    // --- storage ---

    mapping(Safe => mapping(bytes4 => bool)) public safeInterfaces;

    // --- setters ---

    /**
     * Setter to indicate if an interface is supported (and thus reported by ERC165 supportsInterface)
     * @param interfaceId The interface id whose support is to be set
     * @param supported True if the interface is supported, false otherwise
     */
    function setSupportedInterface(bytes4 interfaceId, bool supported) public onlySelf {
        Safe safe = Safe(payable(_manager()));
        // invalid interface id per ERC165 spec
        require(interfaceId != 0xffffffff, "invalid interface id");
        bool current = safeInterfaces[safe][interfaceId];
        if (supported && !current) {
            safeInterfaces[safe][interfaceId] = true;
            emit AddedInterface(safe, interfaceId);
        } else if (!supported && current) {
            delete safeInterfaces[safe][interfaceId];
            emit RemovedInterface(safe, interfaceId);
        }
    }

    /**
     * Batch setter for selectors of an interface
     * @param _interfaceId The interface id to set
     * @param handlerWithSelectors The handlers encoded with the 4-byte selectors of the methods
     */
    function setSupportedInterfaceBatch(bytes4 _interfaceId, bytes32[] calldata handlerWithSelectors)
        external
        onlySelf
    {
        Safe safe = Safe(payable(_msgSender()));
        bytes4 interfaceId;
        for (uint256 i = 0; i < handlerWithSelectors.length; i++) {
            (bool isStatic, bytes4 selector, address handlerAddress) =
                MarshalLib.decodeWithSelector(handlerWithSelectors[i]);
            _setSafeMethod(safe, selector, MarshalLib.encode(isStatic, handlerAddress));
            if (i > 0) {
                interfaceId ^= selector;
            } else {
                interfaceId = selector;
            }
        }

        require(interfaceId == _interfaceId, "interface id mismatch");
        setSupportedInterface(_interfaceId, true);
    }

    /**
     * @notice Implements ERC165 interface detection for the supported interfaces
     * @dev Inheriting contracts should override `_supportsInterface` to add support for additional interfaces
     * @param interfaceId The ERC165 interface id to check
     * @return True if the interface is supported
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return interfaceId == type(IERC165).interfaceId || _supportsInterface(interfaceId)
            || safeInterfaces[Safe(payable(_manager()))][interfaceId];
    }

    // --- internal ---

    /**
     * A stub function to be overridden by inheriting contracts to add support for additional interfaces
     * @param interfaceId The interface id to check support for
     * @return True if the interface is supported
     */
    function _supportsInterface(bytes4 interfaceId) internal view virtual returns (bool);
}
