pragma solidity ^0.8.16;

interface IStaderSlashingManager {
    event SubmittedMisbehavePenalties(uint256 operatorsCount);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);

    function STADER_DAO() external view returns (bytes32);

    function SLASHING_MANAGER_OWNER() external view returns (bytes32);

    function processWithdrawnValidators(bytes[] memory _pubKeys, uint256[] memory _currentBondETH) external;

    function updateBondEthThreshold(uint256 _newBondEthThreshold) external;

    function updateMisbehavePenaltyScore(bytes[] calldata _pubKeys) external;

    function updatePenaltyThreshold(uint256 _newPenaltyThreshold) external;

    function updateBondEthWithPenalties(bytes[] calldata _pubKeys, uint256[] calldata _validatorPenalties) external;

    function updateStaderOperatorRegistry(address _staderOperatorRegistry) external;

    function updateStaderValidatorRegistry(address _staderValidatorRegistry) external;
}
