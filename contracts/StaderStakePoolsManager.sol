// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './ETHX.sol';
import './interfaces/IStaderOracle.sol';
import './interfaces/IStaderPoolBase.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPoolSelector.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/IUserWithdrawalManager.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

/**
 *  @title Liquid Staking Pool Implementation
 *  Stader is a non-custodial smart contract-based staking platform
 *  that helps you conveniently discover and access staking solutions.
 *  We are building key staking middleware infra for multiple PoS networks
 * for retail crypto users, exchanges and custodians.
 */
contract StaderStakePoolsManager is IStaderStakePoolManager, TimelockControllerUpgradeable, PausableUpgradeable {
    using Math for uint256;

    address public ethX;
    address public staderOracle;
    address public userWithdrawalManager;
    address public poolSelector;
    address public poolFactory;
    uint256 public constant DECIMALS = 10**18;
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    uint256 public minWithdrawAmount;
    uint256 public maxWithdrawAmount;
    uint256 public minDepositAmount;
    uint256 public maxDepositAmount;
    uint256 public depositedPooledETH;
    uint256 public paginationLimit;
    uint256 public PERMISSIONLESS_DEPOSIT_SIZE;
    /**
     * @notice Check for zero address
     * @dev Modifier
     * @param _address the address to check
     */
    modifier checkNonZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

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
        address _staderOracle,
        address _userWithdrawManager,
        address[] memory _proposers,
        address[] memory _executors,
        address _timeLockOwner,
        uint256 _minDelay
    )
        external
        initializer
        checkNonZeroAddress(_ethX)
        checkNonZeroAddress(_staderOracle)
        checkNonZeroAddress(_userWithdrawManager)
    {
        __TimelockController_init_unchained(_minDelay, _proposers, _executors, _timeLockOwner);
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        ethX = _ethX;
        staderOracle = _staderOracle;
        userWithdrawalManager = _userWithdrawManager;
        _initialSetup();
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
     * @dev update the minimum withdraw amount
     * @param _minWithdrawAmount minimum withdraw value
     */
    function updateMinWithdrawAmount(uint256 _minWithdrawAmount) external override onlyRole(EXECUTOR_ROLE) {
        if (_minWithdrawAmount == 0) revert InvalidMinWithdrawValue();
        minWithdrawAmount = _minWithdrawAmount;
        emit UpdatedMinWithdrawAmount(minWithdrawAmount);
    }

    /**
     * @dev update the maximum withdraw amount
     * @param _maxWithdrawAmount maximum withdraw value
     */
    function updateMaxWithdrawAmount(uint256 _maxWithdrawAmount) external override onlyRole(EXECUTOR_ROLE) {
        if (_maxWithdrawAmount <= minWithdrawAmount) revert InvalidMaxWithdrawValue();
        maxWithdrawAmount = _maxWithdrawAmount;
        emit UpdatedMaxWithdrawAmount(maxWithdrawAmount);
    }

    /**
     * @dev update ethX address
     * @param _ethX ethX contract
     */
    function updateEthXAddress(address _ethX)
        external
        override
        checkNonZeroAddress(_ethX)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        ethX = _ethX;
        emit UpdatedEthXAddress(ethX);
    }

    /**
     * @dev update stader oracle address
     * @param _staderOracle stader oracle contract
     */
    function updateStaderOracle(address _staderOracle)
        external
        override
        checkNonZeroAddress(_staderOracle)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
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
        checkNonZeroAddress(_userWithdrawalManager)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        userWithdrawalManager = _userWithdrawalManager;
        emit UpdatedUserWithdrawalManager(userWithdrawalManager);
    }

    /**
     * @dev update stader pool selector contract address
     * @param _poolSelector stader pool selector contract
     */
    function updatePoolSelector(address _poolSelector)
        external
        override
        checkNonZeroAddress(_poolSelector)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        poolSelector = _poolSelector;
        emit UpdatedPoolSelector(_poolSelector);
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
        return _convertToAssets(ETHX(ethX).balanceOf(owner), Math.Rounding.Down);
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

    /** @dev See {IERC4626-withdraw}. */
    function userWithdraw(uint256 _ethXAmount, address receiver) public override whenNotPaused {
        uint256 assets = previewWithdraw(_ethXAmount);
        if (assets < minWithdrawAmount || assets > maxWithdrawAmount) revert InvalidWithdrawAmount();
        ETHX(ethX).transferFrom(msg.sender, (address(userWithdrawalManager)), _ethXAmount);
        IUserWithdrawalManager(userWithdrawalManager).withdraw(msg.sender, payable(receiver), assets, _ethXAmount);
        emit WithdrawRequested(msg.sender, receiver, assets, _ethXAmount);
    }

    /**
     * @notice finalize user request in a batch
     * @dev when slashing mode, only process and don't finalize
     * @param _slashingMode mode stating that protocol is getting slashed
     */
    function finalizeUserWithdrawalRequest(bool _slashingMode) external override whenNotPaused onlyRole(EXECUTOR_ROLE) {
        //TODO change input name
        if (!_slashingMode) {
            if (getExchangeRate() == 0) revert ProtocolNotHealthy();
            //batch ID to be finalized next
            uint256 nextBatchIdToFinalize = IUserWithdrawalManager(userWithdrawalManager).nextBatchIdToFinalize();
            //ongoing batch Id
            uint256 latestBatchId = IUserWithdrawalManager(userWithdrawalManager).latestBatchId();
            uint256 maxBatchIdToFinalize = Math.min(latestBatchId, nextBatchIdToFinalize + paginationLimit);
            uint256 lockedEthXToBurn;
            uint256 ethToSendToFinalizeBatch;
            uint256 batchId = 0;
            for (uint256 i = nextBatchIdToFinalize; i < maxBatchIdToFinalize; i++) {
                (, , , uint256 requiredEth, uint256 lockedEthX) = IUserWithdrawalManager(userWithdrawalManager)
                    .batchRequest(batchId);
                uint256 minEThRequiredToFinalizeBatch = Math.min(
                    requiredEth,
                    (lockedEthX * getExchangeRate()) / DECIMALS
                );
                if (minEThRequiredToFinalizeBatch > depositedPooledETH) {
                    break;
                } else {
                    lockedEthXToBurn += lockedEthX;
                    ethToSendToFinalizeBatch += minEThRequiredToFinalizeBatch;
                    depositedPooledETH -= minEThRequiredToFinalizeBatch;
                    batchId = i;
                }
            }
            if (batchId >= nextBatchIdToFinalize) {
                ETHX(ethX).burnFrom(address(userWithdrawalManager), lockedEthXToBurn);
                IUserWithdrawalManager(userWithdrawalManager).finalize{value: ethToSendToFinalizeBatch}(
                    batchId,
                    ethToSendToFinalizeBatch,
                    getExchangeRate()
                );
            }
        }
    }

    function nodeWithdraw(uint256 _operatorId, bytes memory _pubKey)
        public
        override
        whenNotPaused
        returns (uint256 requestId)
    {}

    /**
     * @notice spinning off validators in different pools
     * @dev get pool wise validator to deposit from pool helper and
     * transfer that much eth to individual pool to register on beacon chain
     */
    function validatorBatchDeposit() external override whenNotPaused {
        uint256 pooledETH = depositedPooledETH;
        if (pooledETH < DEPOSIT_SIZE) revert insufficientBalance();
        uint256[] memory poolWiseValidatorsToDeposit = IPoolSelector(poolSelector).computePoolWiseValidatorsToDeposit(
            pooledETH
        );
        for (uint8 i = 1; i < poolWiseValidatorsToDeposit.length; i++) {
            uint256 validatorToDeposit = poolWiseValidatorsToDeposit[i];
            if (validatorToDeposit == 0) continue;
            (string memory poolName, address poolAddress) = IPoolFactory(poolFactory).pools(i);
            uint256 poolDepositSize = (i == 1) ? PERMISSIONLESS_DEPOSIT_SIZE : DEPOSIT_SIZE;
            IStaderPoolBase(poolAddress).registerValidatorsOnBeacon{value: validatorToDeposit * poolDepositSize}();
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
     * @notice initializes variable
     */
    function _initialSetup() internal {
        minDepositAmount = 100;
        maxDepositAmount = 32 ether;
        minWithdrawAmount = 100;
        maxWithdrawAmount = 10 ether;
        paginationLimit = 50;
        PERMISSIONLESS_DEPOSIT_SIZE = 28 ether;
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
        ETHX(ethX).mint(receiver, shares);
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
