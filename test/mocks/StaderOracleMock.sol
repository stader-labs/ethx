// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

contract StaderOracleMock {
    function getSDPriceInETH() external pure returns (uint256) {
        return 1e18 / 1600;
    }
}
