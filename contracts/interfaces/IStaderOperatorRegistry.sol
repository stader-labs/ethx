// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderOperatorRegistry {
    /// @notice event emits after adding a operator to operatorRegistry
    event AddedToOperatorRegistry(uint256 operatorId, uint256 operatorCount);

    /// @notice event emits after increasing validatorCount for an operator
    event IncrementedValidatorCount(uint256 operatorId, uint256 validatorCount);

    /// @notice event emits after increasing activeValidatorCount for an operator
    event IncrementedActiveValidatorCount(uint256 operatorId, uint256 activeValidatorCount);

    /// @notice event emits after increasing the penalty score of a operator for misbehaving
    event ReducedValidatorCount(uint256 operatorId, uint256 validatorCount, uint256 activeActiveCount);

    function operatorCount() external view returns (uint256);

    function STADER_NETWORK_POOL() external view returns (bytes32);

    function STADER_SLASHING_MANAGER() external view returns (bytes32);

    function addToOperatorRegistry(
        bool _optedForSocializingPool,
        address _mevRewardAddress,
        address _operatorRewardAddress,
        bytes32 _staderPoolType,
        string memory _operatorName,
        uint256 _operatorId,
        uint256 _validatorCount,
        uint256 _activeValidatorCount
    ) external;

    function getOperatorIndexById(uint256 _operatorId) external view returns (uint256);

    function incrementActiveValidatorCount(uint256 _operatorId) external;

    function incrementValidatorCount(uint256 _operatorId) external;

    function operatorRegistryIndexByOperatorId(uint256) external view returns (uint256);

    function operatorRegistry(uint256)
        external
        view
        returns (
            bool _optedForSocializingPool,
            address _mevRewardAddress,
            address payable operatorRewardAddress,
            bytes32 staderPoolType,
            string memory operatorName,
            uint256 operatorId,
            uint256 validatorCount,
            uint256 activeValidatorCount
        );

    function reduceOperatorValidatorsCount(uint256 _operatorId) external;

    function selectOperators(
        uint256 _requiredOperatorCount,
        uint256 _operatorStartIndex,
        bytes32 _poolType
    ) external view returns (uint256[] memory outputOperatorIds, uint256 operatorEndIndex);
}
