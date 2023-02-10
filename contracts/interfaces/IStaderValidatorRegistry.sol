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

    function queueToDeposit(uint256) external view returns(uint256);

    function nextValidatorId() external view returns (uint256);

    function markValidatorReadyToDeposit(bytes[] calldata _pubKeys) external;

    function deleteDepositQueueValidator(uint256 _index) external;

    function transferCollateralToPool(uint256 _amount) external ;

    function updateValidatorStatus(bytes calldata _pubKey, ValidatorStatus _status) external;

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
