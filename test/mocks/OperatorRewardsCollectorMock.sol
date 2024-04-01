// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

contract OperatorRewardsCollectorMock {
    function depositFor(address) external payable {}

    function claim(address operator, uint256 amount) public {}

    function getBalance(address) public view returns (uint256) {
        return 0;
    }
}
