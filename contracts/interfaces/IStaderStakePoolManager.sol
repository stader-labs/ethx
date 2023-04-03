// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderStakePoolManager {
    // Errors
    error InvalidDepositAmount();
    error UnsupportedOperation();
    error insufficientBalance();
    error TransferFailed();
    error CallerNotUserWithdrawManager();
    error ProtocolNotInSafeMode();

    // Events
    event UpdatedStaderConfig(address staderConfig);
    event Deposited(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event ExecutionLayerRewardsReceived(uint256 amount);
    event ReceivedExcessEthFromPool(uint8 indexed poolId);
    event TransferredETHToUserWithdrawManager(uint256 amount);
    event ETHTransferredToPool(string indexed poolName, address poolAddress, uint256 validatorCount);
    event WithdrawVaultUserShareReceived(uint256 amount);

    function depositedPooledETH() external view returns (uint256);

    function deposit(address _receiver) external payable returns (uint256);

    function previewDeposit(uint256 _assets) external view returns (uint256);

    function previewWithdraw(uint256 _shares) external view returns (uint256);

    function getExchangeRate() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function convertToShares(uint256 _assets) external view returns (uint256);

    function convertToAssets(uint256 _shares) external view returns (uint256);

    function maxDeposit() external view returns (uint256);

    function receiveExecutionLayerRewards() external payable;

    function receiveWithdrawVaultUserShare() external payable;

    function receiveExcessEthFromPool(uint8 _poolId) external payable;

    function transferETHToUserWithdrawManager(uint256 _amount) external;

    function validatorBatchDeposit() external;
}
