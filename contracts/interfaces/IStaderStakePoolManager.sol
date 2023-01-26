// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderStakePoolManager {
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event NodeDepositReceived(uint256 operatorId, uint256 amount);
    event ExecutionLayerRewardsReceived(uint256 amount);
    event TransferredToPermissionLessPool(address indexed poolAddress, uint256 amount);
    event TransferredToStaderPermissionedPool(address indexed poolAddress, uint256 amount);
    event UpdatedEthXAddress(address account);
    event UpdatedFeePercentage(uint256 fee);
    event UpdatedMaxDepositLimit(uint256 amount);
    event UpdatedMinDepositLimit(uint256 amount);
    event UpdatedPoolWeights(uint256 staderSSVStakePoolWeight, uint256 staderManagedStakePoolWeight);
    event UpdatedPermissionLessPoolAddress(address ssvStakePool);
    event UpdatedSocializingPoolAddress(address executionLayerRewardContract);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);
    event UpdatedStaderOracle(address oracle);
    event UpdatedWithdrawalManagerAddress(address withdrawalManager);
    event UpdatedPermissionedPoolAddresses(address staderStakePool);
    event UpdatedStaderTreasury(address staderTreasury);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event Withdrawn(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event WithdrawalRequested(address indexed recipient, uint256 ethAmount, uint256 sharesAmount, uint256 requestId);

    event WithdrawalClaimed(uint256 indexed requestId, address indexed receiver, address initiator);

    function deposit(address receiver) external payable returns (uint256);

    function initialize(
        address _ethX,
        address _staderSSVStakePoolAddress,
        address _staderManagedStakePoolAddress,
        uint256 _staderSSVStakePoolWeight,
        uint256 _staderManagedStakePoolWeight,
        uint256 _minDelay,
        address[] memory _proposers,
        address[] memory _executors,
        address _timeLockOwner
    ) external;

    function previewDeposit(uint256 assets) external view returns (uint256);

    function previewRedeem(uint256 shares) external view returns (uint256);

    function previewWithdraw(uint256 assets) external view returns (uint256);

    function receiveExecutionLayerRewards() external payable;

    // function redeem(
    //     uint256 shares,
    //     address receiver,
    //     address owner
    // ) external returns (uint256);

    // function withdraw(
    //     uint256 assets,
    //     address receiver,
    //     address owner
    // ) external returns (uint256);
}
