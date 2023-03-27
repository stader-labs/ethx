// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderStakePoolManager {
    //Error events
    error InvalidDepositAmount();
    error UnsupportedOperation();
    error insufficientBalance();
    error TransferFailed();
    error CallerNotUserWithdrawManager();

    // Events
    event Deposited(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event ExecutionLayerRewardsReceived(uint256 amount);
    event ReceivedExcessEthFromPool(uint8 indexed _poolId);
    event TransferredETHToUserWithdrawManager(uint256 _amount);
    event TransferredToPool(string indexed poolName, address poolAddress, uint256 validatorCount);
    event WithdrawVaultUserShareReceived(uint256 amount);

    function depositedPooledETH() external view returns (uint256);

    function deposit(address receiver) external payable returns (uint256);

    function previewDeposit(uint256 assets) external view returns (uint256);

    function previewWithdraw(uint256 shares) external view returns (uint256);

    function getExchangeRate() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function maxDeposit() external view returns (uint256);

    function receiveExecutionLayerRewards() external payable;

    function receiveWithdrawVaultUserShare() external payable;

    function receiveExcessEthFromPool(uint8 _poolId) external payable;

    function transferETHToUserWithdrawManager(uint256 _amount) external;

    function validatorBatchDeposit() external;
}
