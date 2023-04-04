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

    // Constants
    function getStakedEthPerNode() external view returns (uint256);

    function getDecimals() external view returns (uint256);

    function getOperatorMaxNameLength() external view returns (uint256);

    // Variables
    function getSocializingPoolCycleDuration() external view returns (uint256);

    function getSocializingPoolCoolingPeriod() external view returns (uint256);

    function getRewardsThreshold() external view returns (uint256);

    function getMinDepositAmount() external view returns (uint256);

    function getMaxDepositAmount() external view returns (uint256);

    function getMinWithdrawAmount() external view returns (uint256);

    function getMaxWithdrawAmount() external view returns (uint256);

    // Accounts
    function getAdmin() external view returns (address);

    function getStaderTreasury() external view returns (address);

    function getStaderPenaltyFund() external view returns (address);

    // Contracts
    function getTWAPGetter() external view returns (address);

    function getPoolFactory() external view returns (address);

    function getPoolSelector() external view returns (address);

    function getPriceFetcher() external view returns (address);

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

    function getPermissionedNodeRegistry() external view returns (address);

    function getPermissionlessNodeRegistry() external view returns (address);

    function getPermissionedSocializingPool() external view returns (address);

    function getPermissionlessSocializingPool() external view returns (address);

    // Tokens
    function getStaderToken() external view returns (address);

    function getWethToken() external view returns (address);

    function getETHxToken() external view returns (address);
}
