// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';

struct Validator {
    ValidatorStatus status; // state of validator
    bytes pubkey; //public Key of the validator
    bytes preDepositSignature; //signature for 1 ETH deposit on beacon chain
    bytes depositSignature; //signature for 31 ETH deposit on beacon chain
    address withdrawVaultAddress; //eth1 withdrawal address for validator
    uint256 operatorId; // stader network assigned Id
    //TODO do we need this if we are not changing it, we already have collateralETH parameter
    uint256 initialBondEth; // amount of bond eth in gwei
    uint256 depositTime; // time of the 31ETH deposit
    uint256 withdrawnTime; //time when oracle report validator as withdrawn
}

struct Operator {
    bool active; // operator status
    bool optedForSocializingPool; // operator opted for socializing pool
    string operatorName; // name of the operator
    address payable operatorRewardAddress; //Eth1 address of node for reward
    address operatorAddress; //address of operator to interact with stader
}

// Interface for the NodeRegistry contract
interface INodeRegistry {
    // Returns the timestamp of the last time the operator changed the opt-in status for socializing pool
    function getSocializingPoolStateChangeTimestamp(uint256 _operatorId) external view returns (uint256);

    function getAllActiveValidators() external view returns (Validator[] memory);

    function getValidator(bytes calldata _pubkey) external view returns (Validator memory);

    function getValidator(uint256 _validatorId) external view returns (Validator memory);

    /**
    @notice Returns the details of a specific operator.
    @param _pubkey The public key of the validator whose operator details are to be retrieved.
    @return An Operator struct containing the details of the specified operator.
    */
    function getOperator(bytes calldata _pubkey) external view returns (Operator memory);

    /**
     *
     * @param _nodeOperator @notice operator total non withdrawn keys within a specified validator list
     * @param startIndex start index in validator queue to start with
     * @param endIndex  up to end index of validator queue to to count
     */
    function getOperatorTotalNonTerminalKeys(
        address _nodeOperator,
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (uint64);

    function getTotalQueuedValidatorCount() external view returns (uint256); // returns the total number of active validators across all operators

    function getTotalActiveValidatorCount() external view returns (uint256); // returns the total number of queued validators across all operators

    function getCollateralETH() external view returns (uint256);

    function isExistingPubkey(bytes calldata _pubkey) external view returns (bool);
}
