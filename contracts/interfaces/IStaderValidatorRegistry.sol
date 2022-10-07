// File: contracts/interfaces/IStaderValidatorRegistry.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

interface IStaderValidatorRegistry {
    event Initialized(uint8 version);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );
    event addedToValidatorRegistry(bytes publicKey, uint256 count);

    function addToValidatorRegistry(
        bytes memory _pubKey,
        bytes memory _withdrawal_credentials,
        bytes memory _signature,
        bytes32 _deposit_data_root
    ) external;

    function initialize() external;

    function owner() external view returns (address);

    function renounceOwnership() external;

    function setstaderManagedStakePoolAddress(address _staderManagedStakePool)
        external;

    function setstaderSSVStakePoolAddress(address _staderSSVStakePool) external;

    function transferOwnership(address newOwner) external;

    function validatorCount() external view returns (uint256);

    function validatorRegistry(uint256)
        external
        view
        returns (
            bytes memory pubKey,
            bytes memory withdrawal_credentials,
            bytes memory signature,
            bytes32 deposit_data_root,
            bool depositStatus
        );
}
