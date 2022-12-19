// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderPermissionLessValidatorRegistry {
    event AddedToPermissionLessValidatorRegistry(bytes publicKey, uint256 count);
    event Initialized(uint8 version);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function PERMISSION_LESS_POOL() external view returns (bytes32);

    function PERMISSION_LESS_REGISTRY_ADMIN() external view returns (bytes32);

    function addToValidatorRegistry(
        bool _validatorDepositStatus,
        bytes calldata _pubKey,
        bytes calldata _signature,
        bytes32 _depositDataRoot,
        string calldata _nodeName,
        address _nodeRewardAddress,
        uint256 _nodeFees,
        uint256 _bondEth
    ) external;

    function getPoRAddressList(uint256 startIndex, uint256 endIndex) external view returns (string[] memory);

    function getPoRAddressListLength() external view returns (uint256);

    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    function getValidatorIndexByPublicKey(bytes memory _publicKey) external view returns (uint256);

    function grantRole(bytes32 role, address account) external;

    function hasRole(bytes32 role, address account) external view returns (bool);

    function initialize() external;

    function renounceRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function setStaderPermissionLessPoolAddress(address _staderPermissionLessPool) external;

    function staderPermissionLessPool() external view returns (address);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);

    function validatorCount() external view returns (uint256);

    function validatorPubKeyIndex(bytes calldata) external view returns (uint256);

    function validatorRegistry(uint256)
        external
        view
        returns (
            bool validatorDepositStatus,
            bytes calldata pubKey,
            bytes calldata signature,
            bytes32 depositDataRoot,
            address nodeRewardAddress,
            string calldata nodeName,
            uint256 nodeFees,
            uint256 bondEth
        );
}
