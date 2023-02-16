pragma solidity ^0.8.16;

import './INodeRegistry.sol';

interface IStaderPoolBase {
    error NotEnoughCapacity();
    error ValidatorNotInQueue();
    error NotEnoughValidatorToDeposit();

    event UpdatedPoolHelper(address _poolSelector);
    event UpdatedStaderStakePoolManager(address _staderStakePoolManager);
    event ValidatorRegisteredOnBeacon(uint256 indexed _validatorId, bytes _pubKey);

    function registerValidatorsOnBeacon() external payable;

    function updatePoolSelector(address _poolSelector) external;

    function updateStaderStakePoolManager(address _staderStakePoolManager) external;

    function getValidator(bytes memory _pubkey) external view returns (Validator memory);

    function getTotalValidatorCount() external view returns (uint256); // returns the total number of validators across all operators

    function getInitializedValidatorCount() external view returns (uint256); // returns the total number of initialized validators across all operators

    function getActiveValidatorCount() external view returns (uint256); // returns the total number of active validators across all operators

    function getQueuedValidatorCount() external view returns (uint256); // returns the total number of queued validators across all operators

    function getWithdrawnValidatorCount() external view returns (uint256); // returns the total number of withdrawn validators across all operators
}
