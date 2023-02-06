pragma solidity ^0.8.16;

interface IStaderPoolSelector {
    error ZeroAddress();
    error InvalidPoolType();
    error InvalidNewPoolInput();
    error ValidatorsNotAvailable();
    error InvalidDepositWeights();
    error InvalidWithdrawWeights();
    error InvalidExistingWeightUpdateInput();

    event PoolAddressUpdated(uint8 indexed poolType, address poolAddress);
    event NewPoolAdded(uint8 poolType, address poolAddress);
    event UpdatedTotalValidatorKeys(uint8 indexed poolType, uint256 totalValidatorKeys);
    event UpdatedUsedValidatorKeys(uint8 indexed poolType, uint256 usedValidatorKeys);
    event UpdatedWithdrawnValidatorKeys(uint8 indexed poolType, uint256 withdrawnKeys);

    function exitingPoolCount() external view returns (uint8);

    function permissionLessPoolUserDeposit() external view returns (uint256);

    function POOL_SELECTOR_ADMIN() external view returns (bytes32);

    function STADER_NETWORK_POOL() external view returns (bytes32);

    function staderPool(uint8)
        external
        view
        returns (
            uint8 poolType,
            uint8 depositWeight,
            uint8 withdrawWeight,
            address poolAddress,
            uint256 totalValidatorKeys,
            uint256 usedValidatorKeys,
            uint256 withdrawnValidatorKeys
        );

    function poolNameByPoolType(uint8) external view returns (string memory poolName);

    function getValidatorPerPoolToDeposit(uint256 _pooledEth)
        external
        view
        returns (uint256[] memory _poolValidatorShares);

    function addNewPool(
        string calldata _newPoolName,
        address _newPoolAddress,
        uint8[] calldata _newDepositWeights,
        uint8[] calldata _newWithdrawWeights
    ) external;

    function updateExistingDepositWeights(uint8[] calldata _newDepositWeights) external;

    function updateExistingWithdrawWeights(uint8[] calldata _newWithdrawWeights) external;

    function updatePoolAddress(uint8 _poolType, address _poolAddress) external;

    function updateTotalValidatorKeys(uint8 _poolType) external;

    function updateUsedValidatorKeys(uint8 _poolType) external;

    function updateWithdrawnValidatorKeys(uint8 _poolType) external;

    function updatePermissionLessPoolUserDeposit(uint256 _newUserDeposit) external;
}
