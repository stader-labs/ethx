// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import './INodeRegistry.sol';

// Struct representing a pool
struct Pool {
    string poolName;
    address poolAddress;
}

// Interface for the PoolFactory contract
interface IPoolFactory {
    // Errors
    error EmptyString();
    error InvalidPoolID();
    error EmptyNameString();
    error CallerNotManager();
    error PubkeyAlreadyExist();
    error NameCrossedMaxLength();
    error InvalidLengthOfPubkey();
    error InvalidLengthOfSignature();

    // Events
    event PoolAdded(string poolName, address poolAddress);
    event PoolAddressUpdated(uint8 indexed poolId, address poolAddress);
    event UpdatedStaderConfig(address staderConfig);

    // returns the details of a specific pool
    function pools(uint8) external view returns (string calldata poolName, address poolAddress);

    // Pool functions
    function addNewPool(string calldata _poolName, address _poolAddress) external;

    function updatePoolAddress(uint8 _poolId, address _poolAddress) external;

    function retrieveValidator(bytes calldata _pubkey) external view returns (Validator memory);

    function getValidatorByPool(uint8 _poolId, bytes calldata _pubkey) external view returns (Validator memory);

    function retrieveOperator(bytes calldata _pubkey) external view returns (Operator memory);

    function getOperator(uint8 _poolId, bytes calldata _pubkey) external view returns (Operator memory);

    function getOperatorTotalNonTerminalKeys(
        uint8 _poolId,
        address _nodeOperator,
        uint256 _startIndex,
        uint256 _endIndex
    ) external view returns (uint256);

    function getSocializingPoolAddress(uint8 _poolId) external view returns (address);

    // Pool getters
    function getProtocolFee(uint8 _poolId) external view returns (uint256); // returns the protocol fee (0-10000)

    function getOperatorFee(uint8 _poolId) external view returns (uint256); // returns the operator fee (0-10000)

    function poolCount() external view returns (uint8); // returns the number of pools in the factory

    function getTotalActiveValidatorCount() external view returns (uint256); //returns total active validators across all pools

    function getActiveValidatorCountByPool(uint8 _poolId) external view returns (uint256); // returns the total number of active validators in a specific pool

    function getQueuedValidatorCountByPool(uint8 _poolId) external view returns (uint256); // returns the total number of queued validators in a specific pool

    function getCollateralETH(uint8 _poolId) external view returns (uint256);

    function getNodeRegistry(uint8 _poolId) external view returns (address);

    // check for duplicate pubkey across all pools
    function isExistingPubkey(bytes calldata _pubkey) external view returns (bool);

    // check for duplicate operator across all pools
    function isExistingOperator(address _operAddr) external view returns (bool);

    function onlyValidName(string calldata _name) external;

    function onlyValidKeys(
        bytes calldata _pubkey,
        bytes calldata _preDepositSignature,
        bytes calldata _depositSignature
    ) external;
}
