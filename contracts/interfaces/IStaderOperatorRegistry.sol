// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderOperatorRegistry {

    error ZeroAddress();
    error InvalidPoolIdInput();
    error OperatorAlreadyOnBoarded();
    error OperatorNotWhitelisted();
    error OperatorNotRegistered();
    error NoInitializedValidatorLeft();
    error NoQueuedValidatorLeft();
    error NoActiveValidatorLeft();

    event OperatorWhitelisted(uint256 whitelistedNOsCount);
    event IncrementedInitializedValidatorsCount(uint256 operatorId, uint256 initializedValidatorCount);
    event ReducedInitializedValidatorsCount(uint256 operatorId, uint256 initializedValidatorCount);
    event IncrementedQueuedValidatorsCount(uint256 operatorId, uint256 queuedValidatorCount);
    event ReducedQueuedValidatorsCount(uint256 operatorId, uint256 queuedValidatorCount);
    event IncrementedActiveValidatorsCount(uint256 operatorId, uint256 activeValidatorCount);
    event ReducedActiveValidatorsCount(uint256 operatorId, uint256 activeValidatorCount);
    event IncrementedWithdrawnValidatorsCount(uint256 operatorId, uint256 withdrawnValidators);

    function getOperatorCount() external view returns (uint256);

    function STADER_NETWORK_POOL() external view returns (bytes32);

    function OPERATOR_REGISTRY_OWNER() external view returns (bytes32);

    function STADER_SLASHING_MANAGER() external view returns (bytes32);

    function incrementInitializedValidatorsCount(address _nodeOperator) external;

    function reduceInitializedValidatorsCount(address _nodeOperator) external;

    function incrementActiveValidatorsCount(address _nodeOperator) external;

    function reduceActiveValidatorsCount(address _nodeOperator) external;

    function incrementQueuedValidatorsCount(address _nodeOperator) external;

    function reduceQueuedValidatorsCount(address _nodeOperator) external;

    function incrementWithdrawValidatorsCount(address _nodeOperator) external;

    function operatorByOperatorId(uint256) external view returns (address);

    function isWhitelistedPermissionedNO(address) external view returns(bool);

    function whitelistPermissionedNOs(address[] calldata _nodeOperator)
        external;

    function onboardNodeOperator(
        bool _optInForMevSocialize,
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) external returns (address mevFeeRecipientAddress);

    function operatorRegistry(address)
        external
        view
        returns (
            bool optedForSocializingPool,
            string memory operatorName,
            address payable operatorRewardAddress,
            uint256 operatorId,
            uint256 initializedValidatorCount,
            uint256 queuedValidatorCount,
            uint256 activeValidatorCount,
            uint256 withdrawnValidatorCount
        );

    function getTotalValidatorKeys(address _nodeOperator) external view returns (uint256 _totalKeys);
}
