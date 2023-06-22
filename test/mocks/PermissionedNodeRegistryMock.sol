// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import 'forge-std/Test.sol';
import '../../contracts/interfaces/INodeRegistry.sol';

contract PermissionedNodeRegistryMock {
    mapping(uint256 => Validator) public validatorRegistry;

    constructor() {
        validatorRegistry[1].withdrawVaultAddress = address(1);
        validatorRegistry[1].operatorId = 1;
        validatorRegistry[1].pubkey = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        validatorRegistry[1]
            .preDepositSignature = '8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';
    }

    function allocateValidatorsAndUpdateOperatorId(uint256)
        external
        pure
        returns (uint256[] memory selectedOperatorCapacity)
    {
        selectedOperatorCapacity = new uint256[](3);
        selectedOperatorCapacity[0] = 0;
        selectedOperatorCapacity[1] = 0;
        selectedOperatorCapacity[2] = 2;
    }

    function nextQueuedValidatorIndexByOperatorId(uint256) external pure returns (uint256) {
        return 0;
    }

    function updateQueuedValidatorIndex(uint256 _operatorId, uint256 _nextQueuedValidatorIndex) external {}

    function increaseTotalActiveValidatorCount(uint256 _count) external {}

    function updateDepositStatusAndBlock(uint256 _validatorId) external {}

    function markValidatorStatusAsPreDeposit(bytes calldata _pubkey) external {}

    function POOL_ID() external returns (uint8) {}

    function validatorIdsByOperatorId(uint256, uint256) external pure returns (uint256) {
        return 1;
    }

    function validatorIdByPubkey(bytes memory) external returns (uint256) {};

    function onlyPreDepositValidator(bytes memory) external;
}