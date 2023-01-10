// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import '../types/StaderPoolType.sol';

interface IStaderOperatorRegistry {
    event AddedToOperatorRegistry(uint256 operatorId, uint256 operatorCount);
    event IncrementedValidatorCount(uint256 operatorId, uint256 validatorCount);
    event IncrementedActiveValidatorCount(uint256 operatorId, uint256 activeValidatorCount);

    event Initialized(uint8 version);
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);

    function OPERATOR_REGISTRY_ADMIN() external view returns (bytes32);

    function operatorCount() external view returns (uint256);

    function STADER_NETWORK_POOL() external view returns (bytes32);

    function addToOperatorRegistry(
        address _operatorRewardAddress,
        string memory _operatorName,
        StaderPoolType _staderPoolType,
        uint256 _operatorId,
        uint256 _validatorCount,
        uint256 _activeValidatorCount
    ) external;

    function getOperatorIndexById(uint256 _operatorId) external view returns (uint256);

    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

    function hasRole(bytes32 role, address account) external view returns (bool);

    function incrementActiveValidatorCount(uint256 _index) external;

    function incrementValidatorCount(uint256 _index) external;

    function initialize() external;

    function operatorIdIndex(uint256) external view returns (uint256);

    function operatorRegistry(uint256)
        external
        view
        returns (
            address operatorRewardAddress,
            string memory operatorName,
            StaderPoolType staderPoolType,
            uint256 operatorId,
            uint256 validatorCount,
            uint256 activeValidatorCount
        );

    function renounceRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
