// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

import "../Safe.sol";
import "../handler/HandlerContext.sol";

interface IFallbackMethod {
    function handle(Safe safe, address sender, bytes calldata data) external returns (bytes memory result);
}

/**
 * @title Extensible Fallback Handler - Allows for custom handlers to be set for specific methods.
 * @dev This contract allows for intercepting specific methods to override a default fallback function.
 *      Designed to be used with Safe >= 1.3.0.
 * @author mfw78 <mfw78@rndlabs.xyz>
 */
contract ExtensibleFallbackHandler is HandlerContext {
    // Mapping to keep track of custom method handlers for each Safe
    mapping(Safe => mapping(bytes4 => IFallbackMethod)) internal safeMethods;
    // Mapping to keep track of the default fallback handler for each Safe (if overriden)
    mapping(Safe => address) internal defaultFallbackHandlers;

    event AddedSafeMethod(Safe indexed safe, bytes4 selector, IFallbackMethod handler);
    event ChangedSafeMethod(Safe indexed safe, bytes4 selector, IFallbackMethod oldHandler, IFallbackMethod newHandler);
    event RemovedSafeMethod(Safe indexed safe, bytes4 selector);

    event ChangedDefaultFallbackHandler(Safe indexed safe, address oldHandler, address newHandler);

    // Default fallback handler for methods that do not have a custom handler set
    // and where the Safe has not explicitly set a default fallback handler
    address internal immutable defaultFallbackHandler;

    modifier onlySelf() {
        // Use the `HandlerContext._msgSender()` to get the caller of the fallback function
        // Use the `HandlerContext._manager()` to get the manager, which should be the Safe
        // Require that the caller is the Safe itself
        require(_msgSender() == _manager(), "only safe can call this method");
        _;
    }

    /**
     * @notice Constructor that sets the default fallback handler
     * @param _defaultFallbackHandler Address of the default fallback handler
     */
    constructor(address _defaultFallbackHandler) {
        defaultFallbackHandler = _defaultFallbackHandler;
    }

    /**
     * Setter for custom method handlers
     * @param selector The 4-byte selector of the method to set the handler for
     * @param newHandler A contract that implements the IFallbackMethod interface
     */
    function setSafeMethod(bytes4 selector, IFallbackMethod newHandler) external onlySelf {
        Safe safe = Safe(payable(_msgSender()));
        IFallbackMethod oldHandler = safeMethods[safe][selector];
        if (address(newHandler) == address(0) && address(oldHandler) != address(0)) {
            delete safeMethods[safe][selector];
            emit RemovedSafeMethod(safe, selector);
        } else {
            safeMethods[safe][selector] = newHandler;
            if (address(oldHandler) == address(0)) {
                emit AddedSafeMethod(safe, selector, newHandler);
            } else {
                emit ChangedSafeMethod(safe, selector, oldHandler, newHandler);
            }
        }
    }

    /**
     * @notice Setter to override the default fallback handler
     * @dev If a safe's default fallback handler is set to address(0), `defaultFallbackHandler` will be used.
     *      If wanting to disable any default behaviour, set `newHandler` as an address that will revert on any call.
     *      eg. `0xdeaddeaddeaddeaddeaddeaddeaddeaddeaddead`
     * @param newHandler Address of the new default fallback handler
     */
    function setDefaultFallbackHandler(address newHandler) external onlySelf {
        Safe safe = Safe(payable(_msgSender()));
        address oldHandler = defaultFallbackHandlers[safe];
        if (newHandler == address(0) && oldHandler != address(0)) {
            delete defaultFallbackHandlers[safe];
            emit ChangedDefaultFallbackHandler(safe, oldHandler, defaultFallbackHandler);
        } else {
            defaultFallbackHandlers[safe] = newHandler;
            if (oldHandler == address(0)) {
                emit ChangedDefaultFallbackHandler(safe, defaultFallbackHandler, newHandler);
            } else {
                emit ChangedDefaultFallbackHandler(safe, oldHandler, newHandler);
            }
        }
    }

    fallback() external {
        Safe safe = Safe(payable(_manager()));
        address sender = _msgSender();

        address handler = address(safeMethods[safe][msg.sig]);

        bytes memory payloadFromManager = msg.data[:msg.data.length - 20];
        bytes memory callData;
        if (address(handler) != address(0)) {
            callData = abi.encodeCall(IFallbackMethod(handler).handle, (safe, sender, payloadFromManager));
        } else {
            handler = defaultFallbackHandlers[safe];
            // If the safe's default fallback handler is set to address(0), use the default fallback handler
            if (address(handler) == address(0)) {
                handler = defaultFallbackHandler;
            }
            // The vendored `CompatibilityFallbackHandler` expects the last 40 bytes of the calldata to be the safe and sender
            callData = abi.encodePacked(payloadFromManager, safe, sender);
        }

        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Offset of 0x20 is required because of the way Solidity encodes the length of bytes
            let success := call(gas(), handler, 0, add(callData, 0x20), mload(callData), 0, 0)

            returndatacopy(0, 0, returndatasize())
            if iszero(success) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }
}
