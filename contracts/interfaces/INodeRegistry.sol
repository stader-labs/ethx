// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';

struct Validator {
    ValidatorStatus status; // state of validator
    bool isWithdrawal; //status of validator readiness to withdraw
    bytes pubKey; //public Key of the validator
    bytes signature; //signature for deposit to Ethereum Deposit contract
    bytes withdrawalAddress; //eth1 withdrawal address for validator
    uint256 operatorId; // stader network assigned Id
    uint256 bondEth; // amount of bond eth in gwei
}

// Interface for the NodeRegistry contract
interface INodeRegistry {
    function getAllValidators() external view returns (Validator[] memory);

    function getValidator(bytes memory _pubkey) external view returns (Validator memory);

    function getValidator(uint256 _validatorId) external view returns (Validator memory);

    function getTotalValidatorCount() external view returns (uint256); // returns the total number of validators across all operators

    function getInitializedValidatorCount() external view returns (uint256); // returns the total number of initialized validators across all operators

    function getActiveValidatorCount() external view returns (uint256); // returns the total number of active validators across all operators

    function getQueuedValidatorCount() external view returns (uint256); // returns the total number of queued validators across all operators

    function getWithdrawnValidatorCount() external view returns (uint256); // returns the total number of withdrawn validators across all operators
}
