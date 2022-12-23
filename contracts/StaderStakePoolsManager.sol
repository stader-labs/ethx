// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './ETHxVault.sol';
import './interfaces/IStaderValidatorRegistry.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/ISocializingPoolContract.sol';
import './interfaces/IStaderOperatorRegistry.sol';

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
    ETHxVault public ethX;
    IStaderValidatorRegistry public staderValidatorRegistry;
    IStaderOperatorRegistry public staderOperatorRegistry;
    address public socializingPoolAddress;
    address public staderTreasury;
    uint256 public constant DECIMALS = 10**18;
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    uint256 public minDeposit;
    uint256 public maxDeposit;
    uint256 public bufferedEth;
    uint256 public exchangeRate;
    uint256 public totalTVL;
    uint256 public userTVL;
    uint256 public totalELRewardsCollected;
    uint256 public feePercentage;
    bool public isStakePaused;

    struct Pool {
        address poolAddress;
        uint256 poolWeight;
    }
    Pool[] public poolParameters;

    /// @notice Check for zero address
    /// @dev Modifier
    /// @param _address the address to check
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    /**
     * @dev Stader initialized with following variables
     * @param _ethX ethX contract
     * @param _staderSSVStakePoolAddress stader SSV Managed Pool, validator are assigned to operator through SSV
     * @param _staderManagedStakePoolAddress validator are assigned to operator, managed by stader
     * @param _staderSSVStakePoolWeight weight of stader SSV pool, if it is 1 then validator gets operator via SSV
     * @param _staderManagedStakePoolWeight weight of stader managed pool
     * @param _minDelay initial minimum delay for operations
     * @param _proposers accounts to be granted proposer and canceller roles
     * @param _executors  accounts to be granted executor role
     * @param _timeLockOwner multi sig owner of the contract

     */
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
    )
        external
        initializer
        checkZeroAddress(_ethX)
        checkZeroAddress(_staderSSVStakePoolAddress)
        checkZeroAddress(_staderManagedStakePoolAddress)
    {
        require(_staderSSVStakePoolWeight + _staderManagedStakePoolWeight == 100, 'Invalid pool weights');
        __TimelockController_init_unchained(_minDelay, _proposers, _executors, _timeLockOwner);
        __Pausable_init();
        Pool memory _ssvPool = Pool(_staderSSVStakePoolAddress, _staderSSVStakePoolWeight);
        Pool memory _staderPool = Pool(_staderManagedStakePoolAddress, _staderManagedStakePoolWeight);
        ethX = ETHxVault(_ethX);
        poolParameters.push(_ssvPool);
        poolParameters.push(_staderPool);
        _initialSetup();
    }

    // /**
    //  * @notice Send funds to the pool
    //  * @dev Users are able to deposit their funds by transacting to the receive function.
    //  */
    // receive() external payable override{
    //     require(msg.value == 0, "Invalid Amount");
    //     _deposit(address(0));
    // }

    /**
     * @notice Send funds to the pool
     * @dev Users are able to deposit their funds by transacting to the fallback function.
     * protection against accidental submissions by calling non-existent function
     */
    fallback() external payable {
        require(msg.value == 0, 'Invalid Amount');
        _deposit(address(0));
    }

    /**
     * @notice A payable function for execution layer rewards. Can be called only by executionLayerReward Contract
     * @dev We need a dedicated function because funds received by the default payable function
     * are treated as a user deposit
     */
    function receiveExecutionLayerRewards() external payable override {
        require(msg.sender == socializingPoolAddress);
        totalELRewardsCollected += msg.value;
        emit ExecutionLayerRewardsReceived(msg.value);
    }

    /**
     * @notice update the pool to register validators
     * @dev update the pool weights
     */
    function updatePoolWeights(uint256 _staderSSVStakePoolWeight, uint256 _staderManagedStakePoolWeight)
        external
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        require(_staderSSVStakePoolWeight + _staderManagedStakePoolWeight == 100, 'Invalid weights');
        poolParameters[0].poolWeight = _staderSSVStakePoolWeight;
        poolParameters[1].poolWeight = _staderManagedStakePoolWeight;
        emit UpdatedPoolWeights(poolParameters[0].poolWeight, poolParameters[1].poolWeight);
    }

    /**
     * @notice update the pool to register validators
     * @dev update the pool weights
     */
    function updateSSVStakePoolAddresses(address payable _staderSSVStakePoolAddress)
        external
        checkZeroAddress(_staderSSVStakePoolAddress)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        poolParameters[0].poolAddress = _staderSSVStakePoolAddress;
        emit UpdatedSSVStakePoolAddress(poolParameters[0].poolAddress);
    }

    /**
     * @notice update the pool to register validators
     * @dev update the pool weights
     */
    function updateStaderStakePoolAddresses(address payable _staderManagedStakePoolAddress)
        external
        checkZeroAddress(_staderManagedStakePoolAddress)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        poolParameters[1].poolAddress = _staderManagedStakePoolAddress;
        emit UpdatedStaderStakePoolAddress(poolParameters[1].poolAddress);
    }

    /**
     * @dev update the minimum stake amount
     * @param _minDeposit minimum deposit value
     */
    function updateMinDeposit(uint256 _minDeposit) external onlyRole(EXECUTOR_ROLE) {
        require(_minDeposit > 0, 'invalid minDeposit value');
        minDeposit = _minDeposit;
        emit UpdatedMinDeposit(minDeposit);
    }

    /**
     * @dev update the maximum stake amount
     * @param _maxDeposit maximum deposit value
     */
    function updateMaxDeposit(uint256 _maxDeposit) external onlyRole(EXECUTOR_ROLE) {
        require(_maxDeposit > minDeposit, 'invalid maxDeposit value');
        maxDeposit = _maxDeposit;
        emit UpdatedMaxDeposit(maxDeposit);
    }

    /**
     * @dev update ethX address
     * @param _ethX ethX contract
     */
    function updateEthXAddress(address _ethX) external checkZeroAddress(_ethX) onlyRole(EXECUTOR_ROLE) {
        ethX = ETHxVault(_ethX);
        emit UpdatedEthXAddress(address(ethX));
    }

    /**
     * @dev update ELRewardContract address
     * @param _socializingPoolAddress Socializing Pool Address
     */
    function updateSocializingPoolAddress(address _socializingPoolAddress)
        external
        checkZeroAddress(_socializingPoolAddress)
        onlyRole(EXECUTOR_ROLE)
    {
        socializingPoolAddress = _socializingPoolAddress;
        emit UpdatedSocializingPoolAddress(socializingPoolAddress);
    }

    /**
     * @dev update stader treasury address
     * @param _staderTreasury staderTreasury address
     */
    function updateStaderTreasury(address _staderTreasury)
        external
        checkZeroAddress(_staderTreasury)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        staderTreasury = _staderTreasury;
        emit UpdatedStaderTreasury(staderTreasury);
    }

    /**
     * @dev update stader validator registry address
     * @param _staderValidatorRegistry staderValidator Registry address
     */
    function updateStaderValidatorRegistry(address _staderValidatorRegistry)
        external
        checkZeroAddress(_staderValidatorRegistry)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        staderValidatorRegistry = IStaderValidatorRegistry(_staderValidatorRegistry);
        emit UpdatedStaderValidatorRegistry(address(staderValidatorRegistry));
    }

    /**
     * @dev update stader operator registry address
     * @param _staderOperatorRegistry stader operator Registry address
     */
    function updateStaderOperatorRegistry(address _staderOperatorRegistry)
        external
        checkZeroAddress(_staderOperatorRegistry)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        staderOperatorRegistry = IStaderOperatorRegistry(_staderOperatorRegistry);
        emit UpdatedStaderOperatorRegistry(address(staderOperatorRegistry));
    }

    /**
     * @dev update fee percentage
     * @param _feePercentage fee value
     */
    function updateFeePercentage(uint256 _feePercentage) external onlyRole(TIMELOCK_ADMIN_ROLE) {
        feePercentage = _feePercentage;
        emit UpdatedFeePercentage(feePercentage);
    }

    /**
     * @dev update isStakePaused flag
     */
    function toggleIsStakePaused() external onlyRole(EXECUTOR_ROLE) {
        isStakePaused = !isStakePaused;
        emit ToggledIsStakePaused(isStakePaused);
    }

    /**
     * @notice Alternate way to send funds to pool apart from fallback function
     * @dev user deposit their funds with an optional _referral parameter
     */
    function deposit(address _referral) external payable {
        _deposit(_referral);
    }

    /**
     * @notice calculation of exchange Rate
     * @dev exchange rate determines of amount of ethX receive on staking eth
     */
    function updateExchangeRate(
        uint256 _userTVL,
        uint256 _totalTVL,
        uint256 _protocolFee
    ) external onlyRole(EXECUTOR_ROLE) returns (uint256) {
        uint256 ELRewards = ISocializingPoolContract(socializingPoolAddress).withdrawELRewards();
        totalTVL = _totalTVL + ELRewards;
        userTVL = _userTVL + ELRewards;
        uint256 totalSupply = ethX.totalSupply();

        if (totalSupply == 0 || totalTVL == 0) {
            return 1 * DECIMALS;
        } else {
            exchangeRate = (userTVL * DECIMALS) / totalSupply;
        }

        if (_protocolFee > 0) {
            uint256 beaconRewardFeeShares = (_protocolFee * DECIMALS) / exchangeRate;
            ethX.mint(staderTreasury, beaconRewardFeeShares);
        }
        if (ELRewards > 0) {
            _distributeELRewardFee(ELRewards);
        }
        return exchangeRate;
    }

    /**
     * @dev Process user deposit, mints liquid tokens ethX based on exchange Rate
     * @param _referral address of referral.
     */
    function _deposit(address _referral) internal whenNotPaused {
        require(!isStakePaused, 'Staking is paused');
        uint256 amount = msg.value;
        require(amount >= minDeposit && amount <= maxDeposit, 'invalid stake amount');
        uint256 amountToSend = (amount * DECIMALS) / exchangeRate;
        bufferedEth += amount;
        ethX.mint(msg.sender, amountToSend);
        if (address(this).balance >= 32 ether) {
            _selectPool();
        }
        emit Deposited(msg.sender, amount, _referral);
    }

    /**
     * @notice selecting a pool from SSSP and SMSP
     * @dev select a pool based on poolWeight
     */
    function _selectPool() internal {
        uint256 numberOfDeposits = bufferedEth / DEPOSIT_SIZE;
        uint256 amount = numberOfDeposits * DEPOSIT_SIZE;
        bufferedEth -= (amount);

        //slither-disable-next-line low-level-calls
        (bool ssvPoolSuccess, ) = (poolParameters[0].poolAddress).call{
            value: (amount * poolParameters[0].poolWeight) / 100
        }('');
        require(ssvPoolSuccess, 'SSV Pool ETH transfer failed');

        //slither-disable-next-line low-level-calls
        (bool staderPoolSuccess, ) = payable(poolParameters[1].poolAddress).call{
            value: (amount * poolParameters[1].poolWeight) / 100
        }('');
        require(staderPoolSuccess, 'Stader Pool ETH transfer failed');

        emit TransferredToSSVPool(poolParameters[0].poolAddress, (amount * poolParameters[0].poolWeight) / 100);
        emit TransferredToStaderPool(poolParameters[1].poolAddress, (amount * poolParameters[1].poolWeight) / 100);
    }

    /**
     * @notice fee distribution logic on rewards
     * @dev only run when chainlink oracle update beaconChain balance
     */
    function _distributeELRewardFee(uint256 _ELRewards) internal {
        uint256 totalELFee = (_ELRewards * feePercentage) / 100;
        uint256 staderELFee = totalELFee / 2;
        uint256 totalOperatorELFee;
        uint256 totalValidatorRegistered = staderValidatorRegistry.registeredValidatorCount();
        uint256 operatorCount = staderOperatorRegistry.operatorCount();
        for (uint256 index = 0; index < operatorCount; index++) {
            (address operatorRewardAddress, , , , uint256 activeValidatorCount, ) = staderOperatorRegistry
                .operatorRegistry(index);
            uint256 operatorELFee = ((totalELFee - staderELFee) * activeValidatorCount) / totalValidatorRegistered;
            totalOperatorELFee += operatorELFee;
            uint256 operatorELFeeShare = (operatorELFee * DECIMALS) / exchangeRate;
            ethX.mint(operatorRewardAddress, operatorELFeeShare);
        }
        staderELFee = totalELFee - totalOperatorELFee;
        uint256 staderELFeeShare = (staderELFee * DECIMALS) / exchangeRate;
        ethX.mint(staderTreasury, staderELFeeShare);
    }

    function _initialSetup() internal {
        minDeposit = 1;
        maxDeposit = 32 ether;
        feePercentage = 10;
        exchangeRate = 1 * DECIMALS;
    }
}
