// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';

// Interface for the NodeRegistry contract
interface INodeRegistry {
    struct Validator {
        ValidatorStatus status; // state of validator
        bool isFrontRun; // set to true by DAO if validator get front deposit
        bytes pubkey; //public Key of the validator
        bytes signature; //signature for deposit to Ethereum Deposit contract
        address withdrawVaultAddress; //eth1 withdrawal address for validator
        uint256 operatorId; // stader network assigned Id
        uint256 initialBondEth; // amount of bond eth in gwei
    }

    struct Operator {
        bool active; // operator status
        bool optedForSocializingPool; // operator opted for socializing pool
        string operatorName; // name of the operator
        address payable operatorRewardAddress; //Eth1 address of node for reward
        address operatorAddress; //address of operator to interact with stader
        uint256 initializedValidatorCount; //validator whose keys added but not given pre signed msg for withdrawal
        uint256 queuedValidatorCount; // validator queued for deposit
        uint256 activeValidatorCount; // registered validator on beacon chain
        uint256 withdrawnValidatorCount; //withdrawn validator count
    }

    function getTotalQueuedValidatorCount() external view returns (uint256); // returns the total number of active validators across all operators

    function getTotalActiveValidatorCount() external view returns (uint256); // returns the total number of queued validators across all operators
}
