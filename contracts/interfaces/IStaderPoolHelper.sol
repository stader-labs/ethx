pragma solidity ^0.8.16;

interface IStaderPoolHelper {
    error ZeroAddress();
    error InvalidPoolType();
    error NOQueuedValidators();
    error NoActiveValidators();

    event PoolAddressUpdated(uint8 indexed poolType, address poolAddress);
    event NewPoolAdded(uint8 poolType, address poolAddress);
    event UpdatedTotalValidatorKeys(uint8 indexed poolType, uint256 totalValidatorKeys);
    event UpdatedUsedValidatorKeys(uint8 indexed poolType, uint256 usedValidatorKeys);
    event UpdatedWithdrawnValidatorKeys(uint8 indexed poolType, uint256 withdrawnKeys);

    function poolTypeCount() external view returns (uint8);

    function POOL_SELECTOR_ADMIN() external view returns (bytes32);

    function STADER_NETWORK_POOL() external view returns (bytes32);

    function staderPool(uint8)
        external
        view
        returns (
            string calldata poolName,
            address poolAddress,
            uint256 queuedValidatorKeys,
            uint256 activeValidatorKeys,
            uint256 withdrawnValidatorKeys
        );

    function addNewPool(string calldata _newPoolName, address _newPoolAddress) external;

    function updatePoolAddress(uint8 _poolType, address _poolAddress) external;

    function incrementQueuedValidatorKeys(uint8 _poolId) external;

    function reduceQueuedValidatorKeys(uint8 _poolId) external;

    function incrementActiveValidatorKeys(uint8 _poolId) external;

    function reduceActiveValidatorKeys(uint8 _poolId) external;

    function incrementWithdrawnValidatorKeys(uint8 _poolId) external;

    function getQueuedValidator(uint8 _poolId) external view returns (uint256);

    function getActiveValidator(uint8 _poolId) external view returns (uint256);
}
