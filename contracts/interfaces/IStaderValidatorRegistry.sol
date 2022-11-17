// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

interface IStaderValidatorRegistry {
    event AddedToValidatorRegistry(bytes publicKey, uint256 count);
    event Initialized(uint8 version);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    function addToValidatorRegistry(
        bytes memory _pubKey,
        bytes memory _withdrawalCredentials,
        bytes memory _signature,
        bytes32 _depositDataRoot
    ) external;

    function getPoRAddressList() external view returns (string[] memory);

    function getPoRAddressListLength() external view returns (uint256);

    function getValidatorIndexByPublicKey(bytes memory _publicKey)
        external
        view
        returns (uint256);

    function initialize() external;

    function owner() external view returns (address);

    function renounceOwnership() external;

    function setStaderManagedStakePoolAddress(address _staderManagedStakePool)
        external;

    function setStaderSSVStakePoolAddress(address _staderSSVStakePool) external;

    function staderManagedStakePool() external view returns (address);

    function staderSSVStakePool() external view returns (address);

    function transferOwnership(address newOwner) external;

    function validatorCount() external view returns (uint256);

    function validatorRegistry(uint256)
        external
        view
        returns (
            bytes memory pubKey,
            bytes memory withdrawalCredentials,
            bytes memory signature,
            bytes32 depositDataRoot,
            bool depositStatus
        );
}
