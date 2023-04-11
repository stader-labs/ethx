// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './library/AddressLib.sol';

import './ETHx.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/IPoolSelector.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/IStaderOracle.sol';
import './interfaces/IStaderPoolBase.sol';
import './interfaces/IUserWithdrawalManager.sol';
import './interfaces/IStaderStakePoolManager.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
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
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using Math for uint256;
    IStaderConfig public staderConfig;
    uint256 public override depositedPooledETH;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Stader initialized with following variables
     * @param _staderConfig config contract
     */
    function initialize(address _staderConfig) external initializer {
        AddressLib.checkNonZeroAddress(_staderConfig);
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        staderConfig = IStaderConfig(_staderConfig);
        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    // protection against accidental submissions by calling non-existent function
    fallback() external payable {
        revert UnsupportedOperation();
    }

    // protection against accidental submissions by calling non-existent function
    receive() external payable {
        revert UnsupportedOperation();
    }

    // payable function for receiving execution layer rewards.
    function receiveExecutionLayerRewards() external payable override {
        depositedPooledETH += msg.value;
        emit ExecutionLayerRewardsReceived(msg.value);
    }

    // payable function for receiving user share from validator withdraw vault
    function receiveWithdrawVaultUserShare() external payable override {
        depositedPooledETH += msg.value;
        emit WithdrawVaultUserShareReceived(msg.value);
    }

    function receiveEthFromAuction() external payable override {
        depositedPooledETH += msg.value;
        emit AuctionedEthReceived(msg.value);
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
     * @dev only user withdraw manager allowed to call
     * @param _amount amount of ETH to transfer
     */
    function transferETHToUserWithdrawManager(uint256 _amount) external override nonReentrant onlyUserWithdrawManager {
        depositedPooledETH -= _amount;
        //slither-disable-next-line arbitrary-send-eth
        (bool success, ) = payable(staderConfig.getUserWithdrawManager()).call{value: _amount}('');
        if (!success) {
            revert TransferFailed();
        }
        emit TransferredETHToUserWithdrawManager(_amount);
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AddressLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    /**
     * @notice returns the amount of ETH equivalent 1 ETHX (with 18 decimals)
     */
    function getExchangeRate() public view override returns (uint256) {
        uint256 DECIMALS = staderConfig.getDecimals();
        uint256 totalETH = totalAssets();
        uint256 totalETHx = IStaderOracle(staderConfig.getStaderOracle()).getExchangeRate().totalETHXSupply;

        if (totalETH == 0 || totalETHx == 0) {
            return 1 * DECIMALS;
        }
        return (totalETH * DECIMALS) / totalETHx;
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view override returns (uint256) {
        return IStaderOracle(staderConfig.getStaderOracle()).getExchangeRate().totalETHBalance;
    }

    /** @dev See {IERC4626-convertToShares}. */
    function convertToShares(uint256 _assets) public view override returns (uint256) {
        return _convertToShares(_assets, Math.Rounding.Down);
    }

    /** @dev See {IERC4626-convertToAssets}. */
    function convertToAssets(uint256 _shares) public view override returns (uint256) {
        return _convertToAssets(_shares, Math.Rounding.Down);
    }

    /** @dev See {IERC4626-maxDeposit}. */
    function maxDeposit() public view override returns (uint256) {
        return isVaultHealthy() ? staderConfig.getMaxDepositAmount() : 0;
    }

    function minDeposit() public view override returns (uint256) {
        return isVaultHealthy() ? staderConfig.getMinDepositAmount() : 0;
    }

    /** @dev See {IERC4626-previewDeposit}. */
    function previewDeposit(uint256 _assets) public view override returns (uint256) {
        return _convertToShares(_assets, Math.Rounding.Down);
    }

    /** @dev See {IERC4626-previewWithdraw}. */
    function previewWithdraw(uint256 _shares) public view override returns (uint256) {
        return _convertToAssets(_shares, Math.Rounding.Down);
    }

    /** @dev See {IERC4626-deposit}. */
    function deposit(address _receiver) public payable override whenNotPaused returns (uint256) {
        uint256 assets = msg.value;
        if (assets > maxDeposit() || assets < minDeposit()) {
            revert InvalidDepositAmount();
        }
        uint256 shares = previewDeposit(assets);
        _deposit(msg.sender, _receiver, assets, shares);
        return shares;
    }

    /**
     * @notice spinning off validators in different pools
     * @dev get pool wise validator to deposit from pool helper and
     * transfer that much eth to individual pool to register on beacon chain
     */
    function validatorBatchDeposit() external override nonReentrant whenNotPaused {
        if (IStaderOracle(staderConfig.getStaderOracle()).safeMode()) {
            revert UnsupportedOperationInSafeMode();
        }
        uint256 availableETHForNewDeposit = depositedPooledETH -
            IUserWithdrawalManager(staderConfig.getUserWithdrawManager()).ethRequestedForWithdraw();
        address poolFactory = staderConfig.getPoolFactory();
        uint256 ETH_PER_NODE = staderConfig.getStakedEthPerNode();
        if (availableETHForNewDeposit < ETH_PER_NODE) {
            revert InsufficientBalance();
        }
        uint256[] memory selectedPoolCapacity = IPoolSelector(staderConfig.getPoolSelector())
            .computePoolAllocationForDeposit(availableETHForNewDeposit);
        for (uint8 i = 1; i < selectedPoolCapacity.length; i++) {
            uint256 validatorToDeposit = selectedPoolCapacity[i];
            if (validatorToDeposit == 0) {
                continue;
            }
            (string memory poolName, address poolAddress) = IPoolFactory(poolFactory).pools(i);
            uint256 poolDepositSize = ETH_PER_NODE - IPoolFactory(poolFactory).getCollateralETH(i);

            //slither-disable-next-line arbitrary-send-eth
            IStaderPoolBase(poolAddress).stakeUserETHToBeaconChain{value: validatorToDeposit * poolDepositSize}();
            depositedPooledETH -= validatorToDeposit * poolDepositSize;
            emit ETHTransferredToPool(poolName, poolAddress, validatorToDeposit * poolDepositSize);
        }
    }

    /**
     * @dev Triggers stopped state.
     * should not be paused
     */
    function pause() external onlyRole(staderConfig.MANAGER()) {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * should not be paused
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amount of shares.
     */
    function _convertToShares(uint256 _assets, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = IStaderOracle(staderConfig.getStaderOracle()).getExchangeRate().totalETHXSupply;
        return
            (_assets == 0 || supply == 0)
                ? initialConvertToShares(_assets, rounding)
                : _assets.mulDiv(supply, totalAssets(), rounding);
    }

    /**
     * @dev Internal conversion function (from assets to shares) to apply when the vault is empty.
     *
     * NOTE: Make sure to keep this function consistent with {_initialConvertToAssets} when overriding it.
     */
    function initialConvertToShares(
        uint256 _assets,
        Math.Rounding /*rounding*/
    ) internal pure returns (uint256 shares) {
        return _assets;
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 _shares, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = IStaderOracle(staderConfig.getStaderOracle()).getExchangeRate().totalETHXSupply;
        return
            (supply == 0) ? initialConvertToAssets(_shares, rounding) : _shares.mulDiv(totalAssets(), supply, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) to apply when the vault is empty.
     *
     * NOTE: Make sure to keep this function consistent with {initialConvertToShares} when overriding it.
     */
    function initialConvertToAssets(
        uint256 _shares,
        Math.Rounding /*rounding*/
    ) internal pure returns (uint256) {
        return _shares;
    }

    /**
     * @dev Deposit/mint common workflow.
     */
    function _deposit(
        address _caller,
        address _receiver,
        uint256 _assets,
        uint256 _shares
    ) internal {
        ETHx(staderConfig.getETHxToken()).mint(_receiver, _shares);
        depositedPooledETH += _assets;
        emit Deposited(_caller, _receiver, _assets, _shares);
    }

    /**
     * @dev Checks if vault is "healthy" in the sense of having assets backing the circulating shares.
     */
    function isVaultHealthy() private view returns (bool) {
        return
            (totalAssets() > 0 ||
                IStaderOracle(staderConfig.getStaderOracle()).getExchangeRate().totalETHXSupply == 0) && (!paused());
    }

    //modifier
    modifier onlyUserWithdrawManager() {
        if (msg.sender != staderConfig.getUserWithdrawManager()) {
            revert CallerNotUserWithdrawManager();
        }
        _;
    }
}
