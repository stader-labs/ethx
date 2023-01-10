// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderValidatorRegistry {
    event AddedToValidatorRegistry(bytes publicKey, string poolType, uint256 count);
    event Initialized(uint8 version);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function STADER_NETWORK_POOL() external view returns (bytes32);

    function VALIDATOR_REGISTRY_ADMIN() external view returns (bytes32);

    function addToValidatorRegistry(
        bool _validatorDepositStatus,
        bytes memory _pubKey,
        bytes memory _signature,
        bytes32 _depositDataRoot,
        string memory _poolType,
        uint256 _operatorId,
        uint256 _bondEth
    ) external;

    function getPoRAddressList(uint256 startIndex, uint256 endIndex) external view returns (string[] memory);

    function getPoRAddressListLength() external view returns (uint256);

    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    function getValidatorIndexByPublicKey(bytes memory _publicKey) external view returns (uint256);

    function getNextPermissionLessValidator() external view returns (uint256);

    function getNextPermissionedValidator() external view returns (uint256);

    function grantRole(bytes32 role, address account) external;

    function hasRole(bytes32 role, address account) external view returns (bool);

    function incrementRegisteredValidatorCount(bytes memory _publicKey) external;

    function initialize() external;

    function registeredValidatorCount() external view returns (uint256);

    function renounceRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

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
            string memory poolType,
            uint256 operatorId,
            uint256 bondEth
        );
}
