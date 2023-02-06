// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './ETHX.sol';
import './interfaces/IStaderOracle.sol';
import './interfaces/IStaderValidatorRegistry.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IStaderOperatorRegistry.sol';
import './interfaces/IStaderPoolHelper.sol';
import './interfaces/IStaderPool.sol';
import './interfaces/IStaderUserWithdrawalManager.sol';

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

    ETHX public ethX;
    IStaderOracle public staderOracle;
    IStaderUserWithdrawalManager public userWithdrawalManager;
    IStaderPoolHelper public poolSelector;
    uint256 public constant DECIMALS = 10**18;
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    uint256 public minWithdrawAmount;
    uint256 public maxWithdrawAmount;
    uint256 public minDepositAmount;
    uint256 public maxDepositAmount;
    uint256 public depositedPooledETH;
    uint256 public requiredETHForWithdrawal;
    uint256 public permissionedPoolExitingValidatorCount;
    uint256 public permissionLessExitingValidatorCount;
    uint256 public permissionLessPoolUserDeposit;

    /**
     * @notice Check for zero address
     * @dev Modifier
     * @param _address the address to check
     */
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    /**
     * @dev Stader initialized with following variables
     * @param _ethX ethX contract
     * @param _staderOracle stader oracle contract
     * @param _userWithdrawManager user withdraw manager
     * @param _poolSelector pool selector contract
     * @param _minDelay initial minimum delay for operations
     * @param _proposers accounts to be granted proposer and canceller roles
     * @param _executors  accounts to be granted executor role
     * @param _timeLockOwner multi sig owner of the contract

     */
    function initialize(
        address _ethX,
        address _staderOracle,
        address _userWithdrawManager,
        address _poolSelector,
        address[] memory _proposers,
        address[] memory _executors,
        address _timeLockOwner,
        uint256 _minDelay
    )
        external
        initializer
        checkZeroAddress(_ethX)
        checkZeroAddress(_staderOracle)
        checkZeroAddress(_userWithdrawManager)
        checkZeroAddress(_poolSelector)
    {
        __TimelockController_init_unchained(_minDelay, _proposers, _executors, _timeLockOwner);
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        ethX = ETHX(_ethX);
        staderOracle = IStaderOracle(_staderOracle);
        userWithdrawalManager = IStaderUserWithdrawalManager(_userWithdrawManager);
        poolSelector = IStaderPoolHelper(_poolSelector);
        _initialSetup();
    }

    /**
     * @notice Send funds to the pool
     * @dev Users are able to deposit their funds by transacting to the fallback function.
     * protection against accidental submissions by calling non-existent function
     */
    fallback() external payable {
        uint256 assets = msg.value;
        if (assets < minDepositAmount || assets > maxDeposit()) revert InvalidDepositAmount();
        uint256 shares = previewDeposit(assets);
        depositedPooledETH += assets;
        _deposit(_msgSender(), _msgSender(), assets, shares);
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
    function updateEthXAddress(address _ethX) external override checkZeroAddress(_ethX) onlyRole(TIMELOCK_ADMIN_ROLE) {
        ethX = ETHX(_ethX);
        emit UpdatedEthXAddress(address(ethX));
    }

    /**
     * @dev update stader oracle address
     * @param _staderOracle stader oracle contract
     */
    function updateStaderOracle(address _staderOracle)
        external
        override
        checkZeroAddress(_staderOracle)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        staderOracle = IStaderOracle(_staderOracle);
        emit UpdatedStaderOracle(address(staderOracle));
    }

    /**
     * @dev update stader user withdrawal manager address
     * @param _userWithdrawalManager stader user withdrawal Manager contract
     */
    function updateUserWithdrawalManager(address _userWithdrawalManager)
        external
        override
        checkZeroAddress(_userWithdrawalManager)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        userWithdrawalManager = IStaderUserWithdrawalManager(_userWithdrawalManager);
        emit UpdatedUserWithdrawalManager(address(userWithdrawalManager));
    }

    /**
     * @dev update stader pool selector contract address
     * @param _poolSelector stader pool selector contract
     */
    function updatePoolSelector(address _poolSelector)
        external
        override
        checkZeroAddress(_poolSelector)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        poolSelector = IStaderPoolHelper(_poolSelector);
        emit UpdatedPoolSelector(address(_poolSelector));
    }

    /**
     * @notice Returns the amount of ETHER equivalent 1 ETHX (with 18 decimals)
     */
    function getExchangeRate() public view override returns (uint256) {
        uint256 totalETH = totalAssets();
        uint256 totalETHx = staderOracle.totalETHXSupply();

        if (totalETH == 0 || totalETHx == 0) {
            return 1 * DECIMALS;
        }
        return (totalETH * DECIMALS) / totalETHx;
    }

    /** @dev See {IERC4626-totalAssets}. */
    function totalAssets() public view override returns (uint256) {
        return staderOracle.totalETHBalance();
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
        return _convertToAssets(ethX.balanceOf(owner), Math.Rounding.Down);
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
        ethX.transferFrom(msg.sender, (address(userWithdrawalManager)), _ethXAmount);
        requiredETHForWithdrawal += assets;
        userWithdrawalManager.withdraw(msg.sender, payable(receiver), assets, _ethXAmount);
        emit WithdrawRequested(msg.sender, receiver, assets, _ethXAmount);
    }

    /**
     * @notice finalize user request in a batch
     * @dev when slashing mode, only process and don't finalize
     * @param _slashingMode mode stating that protocol is getting slashed
     */
    function finalizeUserWithdrawalRequest(bool _slashingMode) external override whenNotPaused onlyRole(EXECUTOR_ROLE) {
        //TODO change input name
        if (_slashingMode) {
            _processUserWithdrawRequests();
        } else {
            uint256 lastFinalizedBatchNumber = userWithdrawalManager.lastFinalizedBatch();
            uint256 currentBatchNumber = userWithdrawalManager.currentBatchNumber();
            uint256 lockedEthXToBurn;
            uint256 ethToFinalizeBatchesAtWithdrawRate;
            uint256 ethToFinalizeBatchesAtFinalizeRate;
            uint256 updatedFinalizedBatchNumber;
            for (
                updatedFinalizedBatchNumber = lastFinalizedBatchNumber;
                updatedFinalizedBatchNumber < currentBatchNumber;
                ++updatedFinalizedBatchNumber
            ) {
                (, , , uint256 requiredEth, uint256 lockedEthX) = userWithdrawalManager.batchRequest(
                    updatedFinalizedBatchNumber
                );
                lockedEthXToBurn += lockedEthX;
                ethToFinalizeBatchesAtWithdrawRate += requiredEth;
                ethToFinalizeBatchesAtFinalizeRate += (lockedEthX * getExchangeRate()) / DECIMALS;
                if (
                    Math.min(ethToFinalizeBatchesAtWithdrawRate, ethToFinalizeBatchesAtFinalizeRate) >
                    depositedPooledETH
                ) {
                    break;
                }
            }
            if (updatedFinalizedBatchNumber > lastFinalizedBatchNumber) {
                uint256 ethToSendToFinalizeBatch = Math.min(
                    ethToFinalizeBatchesAtWithdrawRate,
                    ethToFinalizeBatchesAtFinalizeRate
                );
                ethX.burnFrom(address(userWithdrawalManager), lockedEthXToBurn);
                userWithdrawalManager.finalize{value: ethToSendToFinalizeBatch}(
                    updatedFinalizedBatchNumber,
                    ethToSendToFinalizeBatch,
                    getExchangeRate()
                );
                requiredETHForWithdrawal -= ethToSendToFinalizeBatch;
                depositedPooledETH -= ethToSendToFinalizeBatch;
            }
            _processUserWithdrawRequests();
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
     * @dev select a pool based on poolWeight
     */
    function transferToPools() external override onlyRole(EXECUTOR_ROLE) {
        uint256 balance = address(this).balance;
        uint256[] memory poolValidatorsCount; //= poolSelector.getValidatorPerPoolToDeposit(balance);
        for (uint8 i = 0; i < poolValidatorsCount.length; i++) {
            if (poolValidatorsCount[i] > 0) {
                (string memory poolName, address poolAddress, , , ) = poolSelector.staderPool(i);
                if (keccak256(abi.encodePacked(poolName)) == keccak256(abi.encodePacked('PERMISSIONLESS'))) {
                    IStaderPool(poolAddress).registerValidatorsOnBeacon{
                        value: poolValidatorsCount[i] * permissionLessPoolUserDeposit
                    }();
                    emit TransferredToPool(poolName, poolAddress, poolValidatorsCount[i]);
                } else {
                    IStaderPool(poolAddress).registerValidatorsOnBeacon{
                        value: poolValidatorsCount[i] * DEPOSIT_SIZE
                    }();
                    emit TransferredToPool(poolName, poolAddress, poolValidatorsCount[i]);
                }
            }
        }
    }

    /**
     * @notice computes validator from each pool to exit to finalize ongoing withdraw requests
     * @dev take into account of exiting validator balance in account
     */
    function _processUserWithdrawRequests() internal view {
        uint256 exitingValidatorsEth = permissionedPoolExitingValidatorCount *
            DEPOSIT_SIZE +
            permissionLessExitingValidatorCount *
            permissionLessPoolUserDeposit;
        if (requiredETHForWithdrawal > exitingValidatorsEth) {
            uint256 ethRequiredByExitingValidator = requiredETHForWithdrawal - exitingValidatorsEth;
            uint256 validatorCountToExit = ethRequiredByExitingValidator / DEPOSIT_SIZE + 1;
            // uint256[] memory poolWiseValidatorCountToExit = poolSelector.getValidatorPerPoolToExit(
            //     validatorCountToExit
            // );
        }
    }

    /**
     * @notice initializes variable
     */
    function _initialSetup() internal {
        minDepositAmount = 100;
        maxDepositAmount = 32 ether;
        minWithdrawAmount = 100;
        maxWithdrawAmount = 10 ether;
        permissionLessPoolUserDeposit = 28 ether;
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amount of shares.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view returns (uint256) {
        uint256 supply = staderOracle.totalETHXSupply();
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
        uint256 supply = staderOracle.totalETHXSupply();
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
        ethX.mint(receiver, shares);
        depositedPooledETH += assets;
        emit Deposited(caller, receiver, assets, shares);
    }

    /**
     * @dev Checks if vault is "healthy" in the sense of having assets backing the circulating shares.
     */
    function _isVaultHealthy() private view returns (bool) {
        return totalAssets() > 0 || staderOracle.totalETHXSupply() == 0;
    }
}
