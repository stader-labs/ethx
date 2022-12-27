// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IStaderStakePoolManager {
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event ExecutionLayerRewardsReceived(uint256 amount);
    event TransferredToSSVPool(address indexed poolAddress, uint256 amount);
    event TransferredToStaderPool(address indexed poolAddress, uint256 amount);
    event UpdatedEthXAddress(address account);
    event UpdatedFeePercentage(uint256 fee);
    event UpdatedMaxDepositLimit(uint256 amount);
    event UpdatedMinDepositLimit(uint256 amount);
    event UpdatedPoolWeights(uint256 staderSSVStakePoolWeight, uint256 staderManagedStakePoolWeight);
    event UpdatedSSVStakePoolAddress(address ssvStakePool);
    event UpdatedSocializingPoolAddress(address executionLayerRewardContract);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);
    event UpdatedStaderOracle(address oracle);
    event UpdatedStaderStakePoolAddress(address staderStakePool);
    event UpdatedStaderTreasury(address staderTreasury);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event Withdrawn(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    // fallback() external payable;

    // function DECIMALS() external view returns (uint256);

    // function DEPOSIT_SIZE() external view returns (uint256);

    // function EXECUTOR_ROLE() external view returns (bytes32);

    // function PROPOSER_ROLE() external view returns (bytes32);

    // function TIMELOCK_ADMIN_ROLE() external view returns (bytes32);

    // function bufferedEth() external view returns (uint256);

    // function convertToAssets(uint256 shares) external view returns (uint256);

    // function convertToShares(uint256 assets) external view returns (uint256);

    function deposit(address receiver) external payable returns (uint256);

    // function ethX() external view returns (address);

    // function feePercentage() external view returns (uint256);

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

    // function maxDeposit(address) external view returns (uint256);

    // function maxDepositLimit() external view returns (uint256);

    // function maxMint(address) external view returns (uint256);

    // function maxRedeem(address owner) external view returns (uint256);

    // function maxWithdraw(address owner) external view returns (uint256);

    // function minDepositLimit() external view returns (uint256);

    function mint(uint256 shares, address receiver) external payable returns (uint256);

    // function oracle() external view returns (address);

    // function poolParameters(uint256)
    //     external
    //     view
    //     returns (address poolAddress, uint256 poolWeight);

    function previewDeposit(uint256 assets) external view returns (uint256);

    function previewMint(uint256 shares) external view returns (uint256);

    function previewRedeem(uint256 shares) external view returns (uint256);

    function previewWithdraw(uint256 assets) external view returns (uint256);

    function receiveExecutionLayerRewards() external payable;

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external returns (uint256);

    // function selectPool() external;

    // function socializingPoolAddress() external view returns (address);

    // function staderOperatorRegistry() external view returns (address);

    // function staderTreasury() external view returns (address);

    // function staderValidatorRegistry() external view returns (address);

    function totalAssets() external view returns (uint256);

    // function totalELRewardsCollected() external view returns (uint256);

    // function updateEthXAddress(address _ethX) external;

    // function updateFeePercentage(uint256 _feePercentage) external;

    // function updateMaxDepositLimit(uint256 _maxDepositLimit) external;

    // function updateMinDepositLimit(uint256 _minDepositLimit) external;

    // function updatePoolWeights(
    //     uint256 _staderSSVStakePoolWeight,
    //     uint256 _staderManagedStakePoolWeight
    // ) external;

    // function updateSSVStakePoolAddresses(address _staderSSVStakePoolAddress)
    //     external;

    // function updateSocializingPoolAddress(address _socializingPoolAddress)
    //     external;

    // function updateStaderOperatorRegistry(address _staderOperatorRegistry)
    //     external;

    // function updateStaderOracle(address _staderOracle) external;

    // function updateStaderStakePoolAddresses(
    //     address _staderManagedStakePoolAddress
    // ) external;

    // function updateStaderTreasury(address _staderTreasury) external;

    // function updateStaderValidatorRegistry(address _staderValidatorRegistry)
    //     external;

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256);

    // receive() external payable;
}
