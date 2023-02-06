pragma solidity ^0.8.16;

contract StaderRoles {
    bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');
    bytes32 public constant SOCIALIZE_POOL_OWNER = keccak256('SOCIALIZE_POOL_OWNER');
    bytes32 public constant REWARD_DISTRIBUTOR = keccak256('REWARD_DISTRIBUTOR');
    bytes32 public constant STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');
    bytes32 public constant STADER_SLASHING_MANAGER = keccak256('STADER_SLASHING_MANAGER');
    bytes32 public constant STADER_PERMISSIONED_POOL_ADMIN = keccak256('STADER_PERMISSIONED_POOL_ADMIN');
    bytes32 public constant PERMISSIONED_POOL = keccak256('PERMISSIONED_POOL');
    bytes32 public constant STADER_PERMISSION_LESS_POOL_ADMIN = keccak256('STADER_PERMISSION_LESS_POOL_ADMIN');
    bytes32 public constant PERMISSION_LESS_OPERATOR = keccak256('PERMISSION_LESS_OPERATOR');
    bytes32 public constant PERMISSION_LESS_POOL = keccak256('PERMISSION_LESS_POOL');
    bytes32 public constant STADER_DAO = keccak256('STADER_DAO');
    bytes32 public constant SLASHING_MANAGER_OWNER = keccak256('SLASHING_MANAGER_OWNER');
    bytes32 public constant POOL_MANAGER = keccak256('POOL_MANAGER');
}
