// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IStaderConfig {
    // Errors
    error InvalidMinDepositValue();
    error InvalidMaxDepositValue();
    error InvalidMinWithdrawValue();
    error InvalidMaxWithdrawValue();

    // Events
    event SetConstant(bytes32, uint256);
    event SetVariable(bytes32, uint256);
    event SetAccount(bytes32, address);
    event SetContract(bytes32, address);
    event SetToken(bytes32, address);

    //Contracts
    function POOL_UTILS() external view returns (bytes32);

    function POOL_SELECTOR() external view returns (bytes32);

    function SD_COLLATERAL() external view returns (bytes32);

    function VAULT_FACTORY() external view returns (bytes32);

    function STADER_ORACLE() external view returns (bytes32);

    function AUCTION_CONTRACT() external view returns (bytes32);

    function PENALTY_CONTRACT() external view returns (bytes32);

    function PERMISSIONED_POOL() external view returns (bytes32);

    function STAKE_POOL_MANAGER() external view returns (bytes32);

    function ETH_DEPOSIT_CONTRACT() external view returns (bytes32);

    function PERMISSIONLESS_POOL() external view returns (bytes32);

    function USER_WITHDRAW_MANAGER() external view returns (bytes32);

    function STADER_INSURANCE_FUND() external view returns (bytes32);

    function PERMISSIONED_NODE_REGISTRY() external view returns (bytes32);

    function PERMISSIONLESS_NODE_REGISTRY() external view returns (bytes32);

    function PERMISSIONED_SOCIALIZING_POOL() external view returns (bytes32);

    function PERMISSIONLESS_SOCIALIZING_POOL() external view returns (bytes32);

    //Roles
    function MANAGER() external view returns (bytes32);

    function OPERATOR() external view returns (bytes32);

    // Constants
    function getStakedEthPerNode() external view returns (uint256);

    function getDecimals() external view returns (uint256);

    function getOperatorMaxNameLength() external view returns (uint256);

    // Variables
    function getSocializingPoolCycleDuration() external view returns (uint256);

    function getSocializingPoolOptInCoolingPeriod() external view returns (uint256);

    function getRewardsThreshold() external view returns (uint256);

    function getMinDepositAmount() external view returns (uint256);

    function getMaxDepositAmount() external view returns (uint256);

    function getMinWithdrawAmount() external view returns (uint256);

    function getMaxWithdrawAmount() external view returns (uint256);

    function getMinBlockDelayToFinalizeWithdrawRequest() external view returns (uint256);

    function getWithdrawnKeyBatchSize() external view returns (uint256);

    // Accounts
    function getAdmin() external view returns (address);

    function getStaderTreasury() external view returns (address);

    // Contracts
    function getPoolUtils() external view returns (address);

    function getPoolSelector() external view returns (address);

    function getSDCollateral() external view returns (address);

    function getVaultFactory() external view returns (address);

    function getStaderOracle() external view returns (address);

    function getAuctionContract() external view returns (address);

    function getPenaltyContract() external view returns (address);

    function getPermissionedPool() external view returns (address);

    function getStakePoolManager() external view returns (address);

    function getETHDepositContract() external view returns (address);

    function getPermissionlessPool() external view returns (address);

    function getUserWithdrawManager() external view returns (address);

    function getStaderInsuranceFund() external view returns (address);

    function getPermissionedNodeRegistry() external view returns (address);

    function getPermissionlessNodeRegistry() external view returns (address);

    function getPermissionedSocializingPool() external view returns (address);

    function getPermissionlessSocializingPool() external view returns (address);

    // Tokens
    function getStaderToken() external view returns (address);

    function getETHxToken() external view returns (address);

    //checks roles and stader contracts
    function onlyStaderContract(address _addr, bytes32 _contractName) external view returns (bool);

    function onlyManagerRole(address account) external view returns (bool);

    function onlyOperatorRole(address account) external view returns (bool);
}
