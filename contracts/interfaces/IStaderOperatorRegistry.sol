// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import '../types/StaderPoolType.sol';

interface IStaderOperatorRegistry {
    /// @notice event emits after adding a operator to operatorRegistry
    event AddedToOperatorRegistry(uint256 operatorId, uint256 operatorCount);

    /// @notice event emits after increasing validatorCount for an operator
    event IncrementedValidatorCount(uint256 operatorId, uint256 validatorCount);

    /// @notice event emits after increasing activeValidatorCount for an operator
    event IncrementedActiveValidatorCount(uint256 operatorId, uint256 activeValidatorCount);

    /// @notice event emits after increasing the penalty score of a operator for misbehaving
    event ReducedValidatorCount(uint256 operatorId, uint256 validatorCount, uint256 activeActiveCount);

    function OPERATOR_REGISTRY_ADMIN() external view returns (bytes32);

    function operatorCount() external view returns (uint256);

    function STADER_NETWORK_POOL() external view returns (bytes32);

    function STADER_SLASHING_MANAGER() external view returns (bytes32);

    function addToOperatorRegistry(
        address _operatorRewardAddress,
        string memory _operatorName,
        StaderPoolType _staderPoolType,
        uint256 _operatorId,
        uint256 _validatorCount,
        uint256 _activeValidatorCount
    ) external;

    function getOperatorIndexById(uint256 _operatorId) external view returns (uint256);

    function incrementActiveValidatorCount(uint256 _operatorId) external;

    function incrementValidatorCount(uint256 _operatorId) external;

    function operatorIdIndex(uint256) external view returns (uint256);

    function operatorRegistry(uint256)
        external
        view
        returns (
            address operatorRewardAddress,
            string memory operatorName,
            StaderPoolType staderPoolType,
            uint256 operatorId,
            uint256 validatorCount,
            uint256 activeValidatorCount
        );

    function reduceOperatorValidatorsCount(uint256 _operatorId) external;
}
