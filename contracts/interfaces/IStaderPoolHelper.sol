pragma solidity ^0.8.16;

interface IStaderPoolHelper {
    error InvalidPoolId();
    error NoQueuedValidators();
    error NoActiveValidators();
    error InvalidNewPoodInput();
    error InvalidNewTargetInput();
    error NoInitializedValidators();

    event PoolAddressUpdated(uint8 indexed poolType, address poolAddress);
    event NewPoolAdded(uint8 poolType, address poolAddress);
    event UpdatedTotalValidatorKeys(uint8 indexed poolType, uint256 totalValidatorKeys);
    event UpdatedUsedValidatorKeys(uint8 indexed poolType, uint256 usedValidatorKeys);
    event UpdatedWithdrawnValidatorKeys(uint8 indexed poolType, uint256 withdrawnKeys);

    function poolCount() external view returns (uint8);

    function POOL_SELECTOR_ADMIN() external view returns (bytes32);

    function STADER_NETWORK_POOL() external view returns (bytes32);

    function staderPool(uint8)
        external
        view
        returns (
            uint8 targetShare,
            string calldata poolName,
            address poolAddress,
            address operatorRegistry,
            address validatorRegistry,
            uint256 initializedValidatorKeys,
            uint256 queuedValidatorKeys,
            uint256 activeValidatorKeys,
            uint256 withdrawnValidatorKeys
        );

    function addNewPool(
        uint8[] calldata _targetSharesstring,
        string calldata _newPoolName,
        address _newPoolAddress,
        address _operatorRegistry,
        address _validatorRegistry
    ) external;

    function updatePoolAddress(uint8 _poolType, address _poolAddress) external;

    function updatePoolOperatorRegistry(uint8 _poolId, address _operatorRegistry) external;

    function updatePoolValidatorRegistry(uint8 _poolId, address _validatorRegistry) external;

    function incrementInitializedValidatorKeys(uint8 _poolId) external;

    function reduceInitializedValidatorKeys(uint8 _poolId) external;

    function incrementQueuedValidatorKeys(uint8 _poolId) external;

    function reduceQueuedValidatorKeys(uint8 _poolId) external;

    function incrementActiveValidatorKeys(uint8 _poolId) external;

    function reduceActiveValidatorKeys(uint8 _poolId) external;

    function incrementWithdrawnValidatorKeys(uint8 _poolId) external;

    function getQueuedValidator(uint8 _poolId) external view returns (uint256);

    function getActiveValidator(uint8 _poolId) external view returns (uint256);

    function getWithdrawnValidator(uint8 _poolId) external view returns (uint256);
}
