// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

library AddressLib {
    error ZeroAddress();

    /// @notice zero address check modifier
    function checkNonZeroAddress(address _address) internal pure {
        if (_address == address(0)) revert ZeroAddress();
    }
}
