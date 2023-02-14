// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderStakePoolManager {
    error InvalidWithdrawAmount();
    error InvalidDepositAmount();
    error InvalidMinDepositValue();
    error InvalidMaxDepositValue();
    error InvalidMinWithdrawValue();
    error InvalidMaxWithdrawValue();
    error ProtocolNotHealthy();
    error UnsupportedOperation();
    error insufficientBalance();

    event Deposited(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event ExecutionLayerRewardsReceived(uint256 amount);
    event ReceivedExcessEthFromPool(uint8 indexed _poolId);
    event TransferredToPool(string indexed poolName, address poolAddress, uint256 validatorCount);
    event UpdatedEthXAddress(address account);
    event UpdatedMaxDepositAmount(uint256 amount);
    event UpdatedMinDepositAmount(uint256 amount);
    event UpdatedMaxWithdrawAmount(uint256 amount);
    event UpdatedMinWithdrawAmount(uint256 amount);
    event UpdatedStaderOracle(address oracle);
    event UpdatedUserWithdrawalManager(address withdrawalManager);
    event UpdatedPoolSelector(address poolSelector);

    event WithdrawRequested(address indexed user, address recipient, uint256 ethAmount, uint256 sharesAmount);

    event WithdrawVaultUserShareReceived(uint256 amount);

    function deposit(address receiver) external payable returns (uint256);

    function previewDeposit(uint256 assets) external view returns (uint256);

    function previewWithdraw(uint256 shares) external view returns (uint256);

    function receiveExecutionLayerRewards() external payable;

    function receiveWithdrawVaultUserShare() external payable;

    function receiveExcessEthFromPool(uint8 _poolId) external payable;

    function updateMinDepositAmount(uint256 _minDepositAmount) external;

    function updateMaxDepositAmount(uint256 _minDepositAmount) external;

    function updateMinWithdrawAmount(uint256 _minWithdrawAmount) external;

    function updateMaxWithdrawAmount(uint256 _minWithdrawAmount) external;

    function updateEthXAddress(address _ethX) external;

    function updateStaderOracle(address _staderOracle) external;

    function updateUserWithdrawalManager(address _userWithdrawalManager) external;

    function updatePoolHelper(address _poolSelector) external;

    function getExchangeRate() external view returns (uint256);

    function totalAssets() external view returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function maxDeposit() external view returns (uint256);

    function maxWithdraw(address owner) external view returns (uint256);

    function userWithdraw(uint256 _ethXAmount, address receiver) external;

    function finalizeUserWithdrawalRequest(bool _slashingMode) external;

    function nodeWithdraw(uint256 _operatorId, bytes memory _pubKey) external returns (uint256 requestId);

    function validatorBatchDeposit() external;
}
