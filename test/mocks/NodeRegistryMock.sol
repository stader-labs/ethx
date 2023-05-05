// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

contract NodeRegistryMock {
    function operatorIDByAddress(address) external pure returns (uint256) {
        return 1;
    }

    function getOperatorTotalKeys(uint256) external pure returns (uint256 totalKeys) {
        return 5;
    }
}
