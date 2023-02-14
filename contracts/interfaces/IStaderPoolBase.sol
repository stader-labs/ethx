pragma solidity ^0.8.16;

interface IStaderPoolBase {

    error NotEnoughCapacity();
    error ValidatorNotInQueue();
    error NotEnoughValidatorToDeposit();

    event UpdatedPoolHelper(address _poolHelper);
    event UpdatedStaderStakePoolManager(address _staderStakePoolManager);
    event ValidatorRegisteredOnBeacon(uint256 indexed _validatorId, bytes _pubKey);

    function registerValidatorsOnBeacon() external payable;

    function updatePoolSelector(address _poolHelper) external;
    
    function updateStaderStakePoolManager(address _staderStakePoolManager)
        external;

}
