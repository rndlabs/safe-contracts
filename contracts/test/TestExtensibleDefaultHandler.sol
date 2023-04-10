// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;

import "../handler/ExtensibleHandlerContext.sol";

/**
 * @title TestExtensibleDefaultHandler - A test ExtensibleHandler default contract
 */
contract TestExtensibleDefaultHandler is ExtensibleHandlerContext {
    /**
     * @notice Returns the sender and manager address provided by the ExtensibleHandlerContext
     * @return sender The sender address
     * @return manager The manager address
     */
    function dudududu() external pure returns (address sender, address manager) {
        return (_msgSender(), _manager());
    }
}
