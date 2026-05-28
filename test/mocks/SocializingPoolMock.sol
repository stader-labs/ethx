// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

contract SocializingPoolMock {
    receive() external payable {}

    function assetCustodied() external pure returns (bool) {
        return false;
    }
}
