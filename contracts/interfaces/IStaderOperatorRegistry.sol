// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderOperatorRegistry {

    error InvalidPoolIdInput();
    error OperatorAlreadyOnBoarded();
    error OperatorNotWhiteListed();
    error OperatorNotRegistered();
    error NoQueuedValidatorLeft();
    error NoActiveValidatorLeft();

    event IncrementedQueuedValidatorsCount(uint256 operatorId, uint256 queuedValidatorCount);
    event ReducedQueuedValidatorsCount(uint256 operatorId, uint256 queuedValidatorCount);
    event IncrementedActiveValidatorsCount(uint256 operatorId, uint256 activeValidatorCount);
    event ReducedActiveValidatorsCount(uint256 operatorId, uint256 activeValidatorCount);
    event IncrementedWithdrawnValidatorsCount(uint256 operatorId, uint256 withdrawnValidators);

    function getOperatorCount() external view returns (uint256);

    function STADER_NETWORK_POOL() external view returns (bytes32);

    function OPERATOR_REGISTRY_OWNER() external view returns (bytes32);

    function STADER_SLASHING_MANAGER() external view returns (bytes32);

    function incrementActiveValidatorsCount(uint256 _operatorId) external;

    function reduceActiveValidatorsCount(uint256 _operatorId) external;

    function incrementQueuedValidatorsCount(uint256 _operatorId) external;

    function reduceQueuedValidatorsCount(uint256 _operatorId) external;

    function incrementWithdrawValidatorsCount(uint256 _operatorId) external;

    function whiteListedPermissionedNOs(address) external view returns (bool);

    function whiteListPermissionedNOs(address _nodeOperator) external;

    function operatorByOperatorId(uint256) external view returns (address);

    function operatorRegistry(address)
        external
        view
        returns (
            bool optedForSocializingPool,
            uint8 staderPoolId,
            string memory operatorName,
            address payable operatorRewardAddress,
            uint256 operatorId,
            uint256 queuedValidatorCount,
            uint256 activeValidatorCount,
            uint256 withdrawnValidatorCount
        );

    function onboardNodeOperator(
        bool _optInForMevSocialize,
        uint8 _poolId,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) external returns (address mevFeeRecipientAddress);

    function getTotalValidatorKeys(address _nodeOperator) external view returns(uint256 _totalKeys);

    function selectOperators(
        uint8 _poolId,
        uint256 _requiredOperatorCount,
        uint256 _operatorStartId

    ) external view returns (uint256[] memory, uint256);
}
