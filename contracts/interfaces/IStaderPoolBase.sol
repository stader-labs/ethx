pragma solidity ^0.8.16;

import './INodeRegistry.sol';

interface IStaderPoolBase {
    //Error events

    error NotEnoughValidatorReadyToDeposit();

    // Events
    event UpdatedNodeRegistryAddress(address _nodeRegistryAddress);
    event UpdatedVaultFactoryAddress(address _vaultFactoryAddress);
    event UpdatedStaderStakePoolManager(address _staderStakePoolManager);
    event ValidatorPreDepositedOnBeaconChain(bytes indexed _pubKey);
    event ValidatorDepositedOnBeaconChain(uint256 indexed _validatorId, bytes _pubKey);

    //Getters

    function getTotalActiveValidatorCount() external view returns (uint256); // returns the total number of active validators across all operators

    function getTotalQueuedValidatorCount() external view returns (uint256); // returns the total number of queued validators across all operators

    function getAllActiveValidators() external view returns (Validator[] memory);

    function getOperatorTotalNonWithdrawnKeys(
        address _nodeOperator,
        uint256 startIndex,
        uint256 endIndex
    ) external view returns (uint256);

    function registerOnBeaconChain() external payable;

    function updateNodeRegistryAddress(address _nodeRegistryAddress) external;

    function updateVaultFactoryAddress(address _vaultFactoryAddress) external;

    function updateStaderStakePoolManager(address _staderStakePoolManager) external;

    function getValidator(bytes memory _pubkey) external view returns (Validator memory);
}
