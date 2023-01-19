// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderValidatorRegistry {
    event AddedToValidatorRegistry(bytes publicKey, bytes32 poolType, uint256 count);

    event RemovedValidatorFromRegistry(bytes publicKey);

    function collateralETH() external view returns (uint256);

    function STADER_NETWORK_POOL() external view returns (bytes32);

    function STADER_SLASHING_MANAGER() external view returns (bytes32);

    function addToValidatorRegistry(
        bool _validatorDepositStatus,
        bytes memory _pubKey,
        bytes memory _signature,
        bytes32 _depositDataRoot,
        bytes32 _staderPoolType,
        uint256 _operatorId,
        uint256 _bondEth
    ) external;

    function getPoRAddressList(uint256 startIndex, uint256 endIndex) external view returns (string[] memory);

    function getPoRAddressListLength() external view returns (uint256);

    function getValidatorIndexByPublicKey(bytes memory _publicKey) external view returns (uint256);

    function getValidatorIndexForOperatorId(bytes32 _poolType, uint256 _inputOperatorId)
        external
        view
        returns (uint256);

    function handleVoluntaryExitValidators(bytes memory _pubKey) external;

    function incrementRegisteredValidatorCount(bytes memory _publicKey) external;

    function registeredValidatorCount() external view returns (uint256);

    function validatorCount() external view returns (uint256);

    function validatorPubKeyIndex(bytes memory) external view returns (uint256);

    function validatorRegistry(uint256)
        external
        view
        returns (
            bool validatorDepositStatus,
            bytes memory pubKey,
            bytes memory signature,
            bytes32 depositDataRoot,
            bytes32 staderPoolType,
            uint256 operatorId,
            uint256 bondEth
        );
}
