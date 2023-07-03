// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import 'forge-std/Test.sol';
import '../../contracts/interfaces/INodeRegistry.sol';
import '../../contracts/interfaces/IPermissionlessPool.sol';

contract PermissionlessNodeRegistryMock {
    mapping(uint256 => Validator) public validatorRegistry;

    constructor() {
        validatorRegistry[1].withdrawVaultAddress = address(1);
        validatorRegistry[1].operatorId = 1;
        validatorRegistry[1].pubkey = '0x8faa339ba46c649885ea0fc9c34d32f9d99c5bde336750';
        validatorRegistry[1]
            .preDepositSignature = '8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';
        validatorRegistry[1]
            .depositSignature = '8faa339ba46c649885ea0fc9c34d32f9d99c5bde3367500ee111075fc390fa48d8dbe155633ad489ee5866e152a5f6';
    }

    function transferCollateralToPool(uint256 _amount) external {
        IPermissionlessPool(msg.sender).receiveRemainingCollateralETH{value: _amount}();
    }

    function nextQueuedValidatorIndex() external pure returns (uint256) {
        return 0;
    }

    function queuedValidators(uint256) external pure returns (uint256) {
        return 1;
    }

    function updateNextQueuedValidatorIndex(uint256) external {}

    function getTotalQueuedValidatorCount() external pure returns (uint256) {
        return 5;
    }

    function getTotalActiveValidatorCount() external pure returns (uint256) {
        return 5;
    }

    function getOperatorTotalNonTerminalKeys(
        address,
        uint256,
        uint256
    ) public pure returns (uint64) {
        return 5;
    }

    function getCollateralETH() external pure returns (uint256) {
        return 4 ether;
    }

    function isExistingPubkey(bytes calldata) external pure returns (bool) {
        return true;
    }

    function isExistingOperator(address) external pure returns (bool) {
        return true;
    }

    function increaseTotalActiveValidatorCount(uint256 _count) external {}

    function updateDepositStatusAndBlock(uint256 _validatorId) external {}

    function POOL_ID() external pure returns (uint8) {
        return 1;
    }
}
