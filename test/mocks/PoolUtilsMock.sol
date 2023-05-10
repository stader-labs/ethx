// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import './NodeRegistryMock.sol';

contract PoolUtilsMock {
    NodeRegistryMock nodeRegistry;
    uint256 operatorTotalNonTerminalKeys;

    constructor() {
        nodeRegistry = new NodeRegistryMock();
        operatorTotalNonTerminalKeys = 5;
    }

    function getOperatorPoolId(address) external pure returns (uint8) {
        return 1;
    }

    function getNodeRegistry(uint8) public view returns (address) {
        return address(nodeRegistry);
    }

    function getOperatorTotalNonTerminalKeys(
        uint8,
        address,
        uint256,
        uint256
    ) public view returns (uint256) {
        return operatorTotalNonTerminalKeys;
    }

    function updateOperatorTotalNonTerminalKeys(bool increase, uint256 numUpdate) public {
        if (increase) {
            operatorTotalNonTerminalKeys += numUpdate;
        } else {
            operatorTotalNonTerminalKeys -= numUpdate;
        }
    }
}
