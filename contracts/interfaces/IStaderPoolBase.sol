pragma solidity ^0.8.16;

import './INodeRegistry.sol';

interface IStaderPoolBase {
    //Error events
    error NotEnoughCapacity();
    error ValidatorNotInQueue();
    error NotEnoughValidatorToDeposit();
    error NotEnoughProcessedBatchToDeposit();

    // Events
    event UpdatedNodeRegistryAddress(address _nodeRegistryAddress);
    event UpdatedVaultFactoryAddress(address _vaultFactoryAddress);
    event UpdatedStaderStakePoolManager(address _staderStakePoolManager);
    event ValidatorPreDepositedOnBeaconChain(uint256 indexed _validatorId, bytes _pubKey);
    event ValidatorDepositedOnBeaconChain(uint256 indexed _validatorId, bytes _pubKey);
    event OperatorFeePercentUpdated(uint256 _operatorFeePercent);
    event ProtocolFeePercentUpdated(uint256 _protocolFeePercent);

    // Setters

    function setProtocolFeePercent(uint256 _protocolFeePercent) external; // sets the protocol fee percent (0-100)

    function setOperatorFeePercent(uint256 _operatorFeePercent) external; // sets the operator fee percent (0-100)

    //Getters

    function protocolFeePercent() external view returns (uint256); // returns the protocol fee percent (0-100)

    function operatorFeePercent() external view returns (uint256); // returns the operator fee percent (0-100)

    function getTotalActiveValidatorCount() external view returns (uint256); // returns the total number of active validators across all operators

    function getTotalQueuedValidatorCount() external view returns (uint256); // returns the total number of queued validators across all operators

    function getAllActiveValidators() external view returns (Validator[] memory);

    function getOperatorTotalNonWithdrawnKeys(address _nodeOperator) external view returns (uint256);

    function registerOnBeaconChain() external payable;

    function updateNodeRegistryAddress(address _nodeRegistryAddress) external;

    function updateVaultFactoryAddress(address _vaultFactoryAddress) external;

    function updateStaderStakePoolManager(address _staderStakePoolManager) external;

    function getValidator(bytes memory _pubkey) external view returns (Validator memory);
}
