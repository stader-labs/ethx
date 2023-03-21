// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './library/Address.sol';

import './ETHx.sol';
import './interfaces/IStaderOracle.sol';
import './interfaces/IStaderPoolBase.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPoolSelector.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/IUserWithdrawalManager.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

/**
 *  @title Liquid Staking Pool Implementation
 *  Stader is a non-custodial smart contract-based staking platform
 *  that helps you conveniently discover and access staking solutions.
 *  We are building key staking middleware infra for multiple PoS networks
 * for retail crypto users, exchanges and custodians.
 */
contract StaderStakePoolsManager is
    IStaderStakePoolManager,
    TimelockControllerUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using Math for uint256;

    address public ethX;
    address public staderOracle;
    address public userWithdrawalManager;
    address public poolSelector;
    address public poolFactory;
    uint256 public constant DECIMALS = 10**18;
    uint256 public minDepositAmount;
    uint256 public maxDepositAmount;
    uint256 public override depositedPooledETH;

    /**
     * @dev Stader initialized with following variables
     * @param _ethX ethX contract
     * @param _staderOracle stader oracle contract
     * @param _userWithdrawManager user withdraw manager
     * @param _minDelay initial minimum delay for operations
     * @param _proposers accounts to be granted proposer and canceller roles
     * @param _executors  accounts to be granted executor role
     * @param _timeLockOwner multi sig owner of the contract

     */
    function initialize(
        address _ethX,
        address _poolFactory,
        address _poolSelector,
        address _staderOracle,
        address _userWithdrawManager,
        address[] memory _proposers,
        address[] memory _executors,
        address _timeLockOwner,
        uint256 _minDelay
    ) external initializer {
        Address.checkNonZeroAddress(_ethX);
        Address.checkNonZeroAddress(_poolFactory);
        Address.checkNonZeroAddress(_poolSelector);
        Address.checkNonZeroAddress(_staderOracle);
        Address.checkNonZeroAddress(_userWithdrawManager);

        __TimelockController_init_unchained(_minDelay, _proposers, _executors, _timeLockOwner);
        __Pausable_init();
        __ReentrancyGuard_init();
        ethX = _ethX;
        poolFactory = _poolFactory;
        poolSelector = _poolSelector;
        staderOracle = _staderOracle;
        userWithdrawalManager = _userWithdrawManager;
        minDepositAmount = 100;
        maxDepositAmount = 32 ether;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Send funds to the pool
     * @dev Users are able to deposit their funds by transacting to the fallback function.
     * protection against accidental submissions by calling non-existent function
     */
    fallback() external payable {
        revert UnsupportedOperation();
    }

    /**
     * @notice A payable function for execution layer rewards.
     */
    function receiveExecutionLayerRewards() external payable override {
        depositedPooledETH += msg.value;
        emit ExecutionLayerRewardsReceived(msg.value);
    }

    function receiveWithdrawVaultUserShare() external payable override {
        depositedPooledETH += msg.value;
        emit WithdrawVaultUserShareReceived(msg.value);
    }

    /**
     * @notice receive the excess ETH from Pools
     * @param _poolId ID of the pool
     */
    function receiveExcessEthFromPool(uint8 _poolId) external payable override {
        depositedPooledETH += msg.value;
        emit ReceivedExcessEthFromPool(_poolId);
    }

    /**
     * @notice transfer the ETH to user withdraw manager to finalize requests
     * @param _amount amount of ETH to transfer
     */
    function transferETHToUserWithdrawManager(uint256 _amount) external override nonReentrant {
        if (msg.sender != userWithdrawalManager) revert CallerNotUserWithdrawManager();
        depositedPooledETH -= _amount;
        //slither-disable-next-line arbitrary-send-eth
        (bool success, ) = payable(userWithdrawalManager).call{value: _amount}('');
        if (!success) revert TransferFailed();
        emit TransferredETHToUserWithdrawManager(_amount);
    }

    /**
     * @dev update the minimum stake amount
     * @param _minDepositAmount minimum deposit value
     */
    function updateMinDepositAmount(uint256 _minDepositAmount) external override onlyRole(EXECUTOR_ROLE) {
        if (_minDepositAmount == 0) revert InvalidMinDepositValue();
        minDepositAmount = _minDepositAmount;
        emit UpdatedMinDepositAmount(minDepositAmount);
    }

    /**
     * @dev update the maximum stake amount
     * @param _maxDepositAmount maximum deposit value
     */
    function updateMaxDepositAmount(uint256 _maxDepositAmount) external override onlyRole(EXECUTOR_ROLE) {
        if (_maxDepositAmount <= minDepositAmount) revert InvalidMaxDepositValue();
        maxDepositAmount = _maxDepositAmount;
        emit UpdatedMaxDepositAmount(maxDepositAmount);
    }

    /**
     * @dev update ethX address
     * @param _ethX ethX contract
     */
    function updateEthXAddress(address _ethX) external override onlyRole(TIMELOCK_ADMIN_ROLE) {
        Address.checkNonZeroAddress(_ethX);
        ethX = _ethX;
        emit UpdatedEthXAddress(ethX);
    }

    /**
     * @dev update stader oracle address
     * @param _staderOracle stader oracle contract
     */
    function updateStaderOracle(address _staderOracle) external override onlyRole(TIMELOCK_ADMIN_ROLE) {
        Address.checkNonZeroAddress(_staderOracle);
        staderOracle = _staderOracle;
        emit UpdatedStaderOracle(staderOracle);
    }

    /**
     * @dev update stader user withdrawal manager address
     * @param _userWithdrawalManager stader user withdrawal Manager contract
     */
    function updateUserWithdrawalManager(address _userWithdrawalManager)
        external
        override
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        Address.checkNonZeroAddress(_userWithdrawalManager);
        userWithdrawalManager = _userWithdrawalManager;
        emit UpdatedUserWithdrawalManager(userWithdrawalManager);
    }

    /**
     * @dev update pool factory address
     * @param _poolFactoryAddress pool factory address
     */
    function updatePoolFactoryAddress(address _poolFactoryAddress) external override onlyRole(TIMELOCK_ADMIN_ROLE) {
        Address.checkNonZeroAddress(_poolFactoryAddress);
        poolFactory = _poolFactoryAddress;
        emit UpdatedPoolFactoryAddress(_poolFactoryAddress);
    }

    /**
     * @dev update stader pool selector contract address
     * @param _poolSelector stader pool selector contract
     */
    function updatePoolSelectorAddress(address _poolSelector) external override onlyRole(TIMELOCK_ADMIN_ROLE) {
        Address.checkNonZeroAddress(_poolSelector);
        poolSelector = _poolSelector;
        emit UpdatedPoolSelectorAddress(_poolSelector);
    }

    /**
     * @notice Returns the amount of ETHER equivalent 1 ETHX (with 18 decimals)
     */
    function getExchangeRate() public view override returns (uint256) {
        uint256 totalETH = totalAssets();
        uint256 totalETHx = IStaderOracle(staderOracle).totalETHXSupply();

        if (totalETH == 0 || totalETHx == 0) {
            return 1 * DECIMALS;
        }
        return (totalETH * DECIMALS) / totalETHx;
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view override returns (uint256) {
        return IStaderOracle(staderOracle).totalETHBalance();
    }

    /** @dev See {IERC4626-convertToShares}. */
    function convertToShares(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Down);
    }

    /** @dev See {IERC4626-convertToAssets}. */
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit() public view override returns (uint256) {
        return _isVaultHealthy() ? maxDepositAmount : 0;
    }

    /** @dev See {IERC4626-maxWithdraw}. */
    function maxWithdraw(address owner) public view override returns (uint256) {
        return _convertToAssets(ETHx(ethX).balanceOf(owner), Math.Rounding.Down);
    }

    /** @dev See {IERC4626-previewDeposit}. */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return _convertToShares(assets, Math.Rounding.Down);
    }

    /** @dev See {IERC4626-previewWithdraw}. */
    function previewWithdraw(uint256 shares) public view override returns (uint256) {
        return _convertToAssets(shares, Math.Rounding.Down);
    }

    /** @dev See {IERC4626-deposit}. */
    function deposit(address receiver) public payable override whenNotPaused returns (uint256) {
        uint256 assets = msg.value;
        if (assets > maxDeposit() || assets < minDepositAmount) revert InvalidDepositAmount();
        uint256 shares = previewDeposit(assets);
        _deposit(msg.sender, receiver, assets, shares);
        return shares;
    }

    /**
     * @notice spinning off validators in different pools
     * @dev get pool wise validator to deposit from pool helper and
     * transfer that much eth to individual pool to register on beacon chain
     */
    function validatorBatchDeposit() external override nonReentrant whenNotPaused {
        uint256 availableETHForNewDeposit = depositedPooledETH -
            IUserWithdrawalManager(userWithdrawalManager).ethRequestedForWithdraw();
        uint256 DEPOSIT_SIZE = IPoolFactory(poolFactory).getBeaconChainDepositSize();
        if (availableETHForNewDeposit < DEPOSIT_SIZE) revert insufficientBalance();
        uint256[] memory selectedPoolCapacity = IPoolSelector(poolSelector).computePoolAllocationForDeposit(
            availableETHForNewDeposit
        );
        for (uint8 i = 1; i < selectedPoolCapacity.length; i++) {
            uint256 validatorToDeposit = selectedPoolCapacity[i];
            if (validatorToDeposit == 0) continue;
            (string memory poolName, address poolAddress) = IPoolFactory(poolFactory).pools(i);
            uint256 poolDepositSize = DEPOSIT_SIZE - IPoolFactory(poolFactory).getCollateralETH(i);

            //slither-disable-next-line arbitrary-send-eth
            IStaderPoolBase(poolAddress).stakeUserETHToBeaconChain{value: validatorToDeposit * poolDepositSize}();
            depositedPooledETH -= validatorToDeposit * poolDepositSize;
            emit TransferredToPool(poolName, poolAddress, validatorToDeposit * poolDepositSize);
        }
    }

    /**
     * @dev Triggers stopped state.
     * should not be paused
     */
    function pause() external onlyRole(EXECUTOR_ROLE) {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * should not be paused
     */
    function unpause() external onlyRole(EXECUTOR_ROLE) {
        _unpause();
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amount of shares.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = IStaderOracle(staderOracle).totalETHXSupply();
        return
            (assets == 0 || supply == 0)
                ? _initialConvertToShares(assets, rounding)
                : assets.mulDiv(supply, totalAssets(), rounding);
    }

    /**
     * @dev Internal conversion function (from assets to shares) to apply when the vault is empty.
     *
     * NOTE: Make sure to keep this function consistent with {_initialConvertToAssets} when overriding it.
     */
    function _initialConvertToShares(
        uint256 assets,
        Math.Rounding /*rounding*/
    ) internal pure returns (uint256 shares) {
        return assets;
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = IStaderOracle(staderOracle).totalETHXSupply();
        return
            (supply == 0) ? _initialConvertToAssets(shares, rounding) : shares.mulDiv(totalAssets(), supply, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) to apply when the vault is empty.
     *
     * NOTE: Make sure to keep this function consistent with {_initialConvertToShares} when overriding it.
     */
    function _initialConvertToAssets(
        uint256 shares,
        Math.Rounding /*rounding*/
    ) internal pure returns (uint256) {
        return shares;
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal {
        ETHx(ethX).mint(receiver, shares);
        depositedPooledETH += assets;
        emit Deposited(caller, receiver, assets, shares);
    }

    /**
     * @dev Checks if vault is "healthy" in the sense of having assets backing the circulating shares.
     */
    function _isVaultHealthy() private view returns (bool) {
        return totalAssets() > 0 || IStaderOracle(staderOracle).totalETHXSupply() == 0;
    }
}
