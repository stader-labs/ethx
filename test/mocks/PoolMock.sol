// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

contract PoolMock {
    address nodeRegistry;

    constructor(address _nodeRegistry) {
        nodeRegistry = _nodeRegistry;
    }

    function getNodeRegistry() external view returns (address) {
        return nodeRegistry;
    }

    function protocolFee() external pure returns (uint256) {
        return 500;
    }

    function operatorFee() external pure returns (uint256) {
        return 500;
    }

    function stakeUserETHToBeaconChain() external payable {}

}
