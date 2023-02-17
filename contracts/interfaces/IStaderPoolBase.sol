pragma solidity ^0.8.16;

interface IStaderPoolBase {
    //Error events

    error NotEnoughCapacity();
    error ValidatorNotInQueue();
    error NotEnoughValidatorToDeposit();

    // Events
    event UpdatedNodeRegistryAddress(address _nodeRegistryAddress);
    event UpdatedVaultFactoryAddress(address _vaultFactoryAddress);
    event UpdatedStaderStakePoolManager(address _staderStakePoolManager);
    event ValidatorRegisteredOnBeacon(uint256 indexed _validatorId, bytes _pubKey);

    //Getters

    function getTotalValidatorCount() external view returns (uint256); // returns the total number of validators across all operators

    function getTotalInitializedValidatorCount() external view returns (uint256); // returns the total number of initialized validators across all operators

    function getTotalActiveValidatorCount() external view returns (uint256); // returns the total number of active validators across all operators

    function getTotalQueuedValidatorCount() external view returns (uint256); // returns the total number of queued validators across all operators

    function getTotalWithdrawnValidatorCount() external view returns (uint256); // returns the total number of withdrawn validators across all operators

    //Setters

    function registerValidatorsOnBeacon() external payable;

    function updateNodeRegistryAddress(address _nodeRegistryAddress) external;

    function updateVaultFactoryAddress(address _vaultFactoryAddress) external;

    function updateStaderStakePoolManager(address _staderStakePoolManager) external;
}
