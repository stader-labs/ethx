pragma solidity ^0.8.16;

interface IStaderPoolBase {
    error NotEnoughCapacity();
    error ValidatorNotInQueue();
    error NotEnoughValidatorToDeposit();

    event UpdatedStaderStakePoolManager(address _staderStakePoolManager);
    event ValidatorRegisteredOnBeacon(uint256 indexed _validatorId, bytes _pubKey);

    function registerValidatorsOnBeacon() external payable;

    function updateStaderStakePoolManager(address _staderStakePoolManager) external;

    function getTotalValidatorCount() external view returns (uint256); // returns the total number of validators across all operators

    function getTotalInitializedValidatorCount() external view returns (uint256); // returns the total number of initialized validators across all operators

    function getTotalActiveValidatorCount() external view returns (uint256); // returns the total number of active validators across all operators

    function getTotalQueuedValidatorCount() external view returns (uint256); // returns the total number of queued validators across all operators

    function getTotalWithdrawnValidatorCount() external view returns (uint256); // returns the total number of withdrawn validators across all operators
}
