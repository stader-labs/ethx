// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderStakePoolManager {
    event Deposited(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event ExecutionLayerRewardsReceived(uint256 amount);
    event TransferredToPool(uint8 indexed poolType, address poolAddress, uint256 validatorCount);
    event UpdatedEthXAddress(address account);
    event UpdatedFeePercentage(uint256 fee);
    event UpdatedMaxDepositAmount(uint256 amount);
    event UpdatedMinDepositAmount(uint256 amount);
    event UpdatedMaxWithdrawAmount(uint256 amount);
    event UpdatedMinWithdrawAmount(uint256 amount);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);
    event UpdatedStaderOracle(address oracle);
    event UpdatedUserWithdrawalManager(address withdrawalManager);
    event UpdatedPoolSelector(address poolSelector);
    event UpdatedStaderTreasury(address staderTreasury);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event Withdrawn(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event WithdrawRequested(
        address indexed user,
        address recipient,
        uint256 ethAmount,
        uint256 sharesAmount
    );

    event WithdrawVaultUserShareReceived(uint256 amount);

    function deposit(address receiver) external payable returns (uint256);

    function previewDeposit(uint256 assets) external view returns (uint256);

    function previewWithdraw(uint256 shares) external view returns (uint256);

    function receiveExecutionLayerRewards() external payable;

    function receiveWithdrawVaultRewards() external payable;
}
