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

    function getOperatorRewardAddress(uint256) external pure returns (address) {
        return address(2);
    }

    function getOperatorTotalKeys(uint256) external pure returns (uint256 totalKeys) {
        return 5;
    }

    function POOL_ID() external pure returns (uint8) {
        return 1;
    }

    function getTotalQueuedValidatorCount() external pure returns (uint256) {
        return 10;
    }

    function getTotalActiveValidatorCount() external pure returns (uint256) {
        return 10;
    }

    function getCollateralETH() external pure returns (uint256) {
        return 4 ether;
    }

    function markValidatorReadyToDeposit(
        bytes[] calldata,
        bytes[] calldata,
        bytes[] calldata
    ) external {}

    function withdrawnValidators(bytes[] calldata) external {}
}
