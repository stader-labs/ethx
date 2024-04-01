// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.16;

contract WETHMock {
    function deposit() external payable {}

    function withdraw(uint256) external {}

    function transferFrom(
        address src,
        address dst,
        uint256 wad
    ) external returns (bool) {
        return true;
    }
}
