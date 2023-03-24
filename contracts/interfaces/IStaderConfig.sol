// SPDX-License-Identifier: MIT
pragma solidity >=0.7.5;

interface IStaderConfig {
    //error
    error InvalidMinDepositValue();
    error InvalidMaxDepositValue();
    error InvalidMinWithdrawValue();
    error InvalidMaxWithdrawValue();

    // events
    event SetConstant(uint256, uint256);
    event SetVariable(uint256, uint256);
    event SetAccount(uint256, address);
    event SetContract(uint256, address);
    event SetToken(uint256, address);
    event SetPoolId(bytes32, uint8);

    // Constants
    function getFullDepositOnBeaconChain() external view returns (uint256);

    function getDecimals() external view returns (uint256);

    function getOperatorMaxNameLength() external view returns (uint256);

    // Variables
    function getRewardsThreshold() external view returns (uint256);

    function getMinDepositAmount() external view returns (uint256);

    function getMaxDepositAmount() external view returns (uint256);

    function getMinWithdrawAmount() external view returns (uint256);

    function getMaxWithdrawAmount() external view returns (uint256);

    // Accounts
    function getMultiSigAdmin() external view returns (address);

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

    function getPenaltyContract() external view returns (address);

    function getPermissionedPool() external view returns (address);

    function getStakePoolManager() external view returns (address);

    function getETHDepositContract() external view returns (address);

    function getPermissionlessPool() external view returns (address);

    function getUserWithdrawManager() external view returns (address);

    function getPermissionedNodeRegistry() external view returns (address);

    function getPermissionlessNodeRegistry() external view returns (address);

    function getPermissionedSocializePool() external view returns (address);

    function getPermissionlessSocializePool() external view returns (address);

    // Tokens
    function getStaderToken() external view returns (address);

    function getWethToken() external view returns (address);

    function getETHxToken() external view returns (address);
}
