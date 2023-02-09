// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../library/ValidatorStatus.sol';

interface IStaderValidatorRegistry {
    error TransferFailed();
    error OperatorNotOnBoarded();
    error InvalidBondEthValue();
    error OperatorNotWhitelisted();

    event AddedToValidatorRegistry(bytes publicKey, bytes32 poolType, uint256 count);

    event RemovedValidatorFromRegistry(bytes publicKey);

    function collateralETH() external view returns (uint256);

    function STADER_NETWORK_POOL() external view returns (bytes32);

    function STADER_SLASHING_MANAGER() external view returns (bytes32);

    function addValidatorKeys(
        bytes calldata _validatorPubKey,
        bytes calldata _validatorSignature,
        bytes32 _depositDataRoot
    ) external payable;

    function validatorIdByPubKey(bytes memory _publicKey) external view returns (uint256);

    function getValidatorIndexForOperatorId(uint8 _poolId, uint256 _inputOperatorId) external view returns (uint256);

    function handleWithdrawnValidators(bytes memory _pubKey) external;

    function increasePenaltyCount(uint256 validatorIndex) external;

    function incrementRegisteredValidatorCount(bytes memory _publicKey) external;

    function markValidatorReadyForWithdrawal(uint256 validatorIndex) external;

    function registeredValidatorCount() external view returns (uint256);

    function updateBondEth(uint256 validatorIndex, uint256 currentBondEth) external;

    function nextValidatorId() external view returns (uint256);

    function validatorRegistry(uint256)
        external
        view
        returns (
            ValidatorStatus status,
            bool isWithdrawal,
            bytes memory pubKey,
            bytes memory signature,
            bytes memory withdrawalAddress,
            bytes32 depositDataRoot,
            uint256 operatorId,
            uint256 bondEth,
            uint256 penaltyCount
        );
}
