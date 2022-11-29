// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderValidatorRegistry {
    event Initialized(uint8 version);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AddedToValidatorRegistry(bytes publicKey, uint256 count);

    function addToValidatorRegistry(
        bytes memory _pubKey,
        bytes memory _withdrawalCredentials,
        bytes memory _signature,
        bytes32 _depositDataRoot
    ) external;

    function initialize() external;

    function owner() external view returns (address);

    function renounceOwnership() external;

    function setStaderManagedStakePoolAddress(address _staderManagedStakePool) external;

    function setStaderSSVStakePoolAddress(address _staderSSVStakePool) external;

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
