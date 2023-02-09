pragma solidity ^0.8.16;

library Address {

    error ZeroAddress();

    /// @notice zero address check modifier
    function checkZeroAddress(address _address) public pure {
        if (_address == address(0)) revert ZeroAddress();
    }
    
}
