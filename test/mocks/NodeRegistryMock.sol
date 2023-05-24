// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '../../contracts/interfaces/INodeRegistry.sol';

contract NodeRegistryMock {
    mapping(uint256 => Validator) public validatorRegistry;
    mapping(uint256 => Operator) public operatorStructById;

    constructor() {
        validatorRegistry[1].withdrawVaultAddress = address(1);
        validatorRegistry[1].operatorId = 1;
        validatorRegistry[1].pubkey = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';

        operatorStructById[1].operatorAddress = address(500);
    }

    function operatorIDByAddress(address) external pure returns (uint256) {
        return 1;
    }

    function getOperatorTotalKeys(uint256) external pure returns (uint256 totalKeys) {
        return 5;
    }
}
