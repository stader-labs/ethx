// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./EthX.sol";
import "./interfaces/IStaderValidatorRegistry.sol";
import "./interfaces/IStaderStakePoolManager.sol";
import "./interfaces/IExecutionLayerRewardContract.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/**
 *  @title Liquid Staking Pool Implementation
 *  Stader is a non-custodial smart contract-based staking platform
 *  that helps you conveniently discover and access staking solutions.
 *  We are building key staking middleware infra for multiple PoS networks
 * for retail crypto users, exchanges and custodians.
 */
contract StaderStakePoolsManager is IStaderStakePoolManager, TimelockControllerUpgradeable, PausableUpgradeable {

    ETHX public ethX;
    AggregatorV3Interface internal ethXFeed;
    IStaderValidatorRegistry validatorRegistry;
    address public executionLayerRewardContract;
    address public staderTreasury;
    uint256 public constant DECIMALS = 10**18;
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    uint256 public minDeposit;
    uint256 public maxDeposit;
    uint256 public bufferedEth;
    uint256 public prevBeaconChainReward;
    uint256 public exchangeRate;
    uint256 public totalTVL;
    uint256 public oracleLastUpdatedAt;
    uint256 public totalELRewardsCollected;
    uint256 public feePercentage;
    bool public isStakePaused;

    struct pool{
        address poolAddress;
        uint256 poolWeight;
    }
    pool[] public poolParameters;

    /// @notice Check for zero address
    /// @dev Modifier
    /// @param _address the address to check
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), "Address cannot be zero");
        _;
    }

    /**
     * @dev Stader initialized with following variables
     * @param _ethX ethX contract
     * @param _ethXFeed chainlink POR contract
     * @param _staderSSVStakePoolAddress stader SSV Managed Pool, validator are assigned to operator through SSV
     * @param _staderManagedStakePoolAddress validator are assigned to operator, managed by stader
     * @param _staderSSVStakePoolWeight weight of stader SSV pool, if it is 1 then validator gets operator via SSV
     * @param _staderManagedStakePoolWeight weight of stader managed pool
     * @param _timeLockOwner multi sig owner of the contract

     */
    function initialize(
        address _ethX,
        address _ethXFeed,
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
        checkZeroAddress(_ethXFeed)
        checkZeroAddress(_staderSSVStakePoolAddress)
        checkZeroAddress(_staderManagedStakePoolAddress)
    {
        require(
            _staderSSVStakePoolWeight + _staderManagedStakePoolWeight == 100,
            "Invalid pool weights"
        );
        __Pausable_init();
        __TimelockController_init_unchained(_minDelay, _proposers,_executors,_timeLockOwner);        
        ethX = ETHX(_ethX);
        ethXFeed = AggregatorV3Interface(_ethXFeed);
        poolParameters[0].poolAddress = _staderSSVStakePoolAddress;
        poolParameters[0].poolWeight = _staderSSVStakePoolWeight;
        poolParameters[1].poolAddress = _staderManagedStakePoolAddress;
        poolParameters[1].poolWeight = _staderManagedStakePoolWeight;
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
        require(msg.value == 0, "Invalid Amount");
        _deposit(address(0));
    }

    /**
    * @notice A payable function for execution layer rewards. Can be called only by executionLayerReward Contract
    * @dev We need a dedicated function because funds received by the default payable function
    * are treated as a user deposit
    */
    function receiveExecutionLayerRewards() external payable override{
        require(msg.sender == executionLayerRewardContract);
        totalELRewardsCollected += msg.value;
        emit ExecutionLayerRewardsReceived(msg.value);
    }

    /**
     * @notice update the pool to register validators
     * @dev update the pool weights
     */
    function updatePoolWeights(
        uint256 _staderSSVStakePoolWeight,
        uint256 _staderManagedStakePoolWeight
    ) external  onlyRole(TIMELOCK_ADMIN_ROLE) {
        require(
            _staderSSVStakePoolWeight + _staderManagedStakePoolWeight == 100,
            "Invalid weights"
        );
        poolParameters[0].poolWeight = _staderSSVStakePoolWeight;
        poolParameters[1].poolWeight = _staderManagedStakePoolWeight;
        emit UpdatedPoolWeights(poolParameters[0].poolWeight,  poolParameters[1].poolWeight);
    }

    /**
     * @notice update the pool to register validators
     * @dev update the pool weights
     */
    function updateSSVStakePoolAddresses(
        address payable _staderSSVStakePoolAddress
    ) external checkZeroAddress(_staderSSVStakePoolAddress)  onlyRole(TIMELOCK_ADMIN_ROLE) {
        poolParameters[0].poolAddress = _staderSSVStakePoolAddress;
        emit UpdatedSSVStakePoolAddress(poolParameters[0].poolAddress);
    }

    /**
     * @notice update the pool to register validators
     * @dev update the pool weights
     */
    function updateStaderStakePoolAddresses(
        address payable _staderManagedStakePoolAddress
    )
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
    function updateMinDeposit(uint256 _minDeposit) external onlyRole(EXECUTOR_ROLE){
        require(_minDeposit > 0, "invalid minDeposit value");
        minDeposit = _minDeposit;
        emit UpdatedMinDeposit(minDeposit);
    }

    /**
     * @dev update the maximum stake amount
     * @param _maxDeposit maximum deposit value
     */
    function updateMaxDeposit(uint256 _maxDeposit) external onlyRole(EXECUTOR_ROLE) {
        require(_maxDeposit > minDeposit, "invalid maxDeposit value");
        maxDeposit = _maxDeposit;
        emit UpdatedMaxDeposit(maxDeposit);
    }

    /**
     * @dev update ethX feed
     * @param _ethXFeed ethX contract
     */
    function updateEthXFeed(address _ethXFeed)
        external
        checkZeroAddress(_ethXFeed)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        ethXFeed = AggregatorV3Interface(_ethXFeed);
        emit UpdatedEthXFeed(address(_ethXFeed));
    }

    /**
     * @dev update ethX address
     * @param _ethX ethX contract
     */
    function updateEthXAddress(address _ethX)
        external
        checkZeroAddress(_ethX)
        onlyRole(EXECUTOR_ROLE)
    {
        ethX = ETHX(_ethX);
        emit UpdatedEthXAddress(address(ethX));
    }

    /**
     * @dev update ELRewardContract address
     * @param _executionLayerRewardContract EL reward contract
     */
    function updateELRewardContract(address _executionLayerRewardContract)
        external
        checkZeroAddress(_executionLayerRewardContract)
        onlyRole(EXECUTOR_ROLE)
    {
        executionLayerRewardContract = _executionLayerRewardContract;
        emit UpdatedELRewardContract(executionLayerRewardContract);
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
     * @param _validatorRegistry staderValidator Registry address
     */
    function updateStaderValidatorRegistry(address _validatorRegistry)
        external
        checkZeroAddress(_validatorRegistry)
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        validatorRegistry = IStaderValidatorRegistry(_validatorRegistry);
        emit UpdatedStaderValidatorRegistry(address(validatorRegistry));
    }

    /**
     * @dev update fee percentage
     * @param _feePercentage fee value
     */
    function updateFeePercentage(uint256 _feePercentage)
        external
        onlyRole(TIMELOCK_ADMIN_ROLE)
    {
        feePercentage = _feePercentage;
        emit UpdatedFeePercentage(feePercentage);
    }

    /**
     * @dev update isStakePaused flag
     */
    function toggleIsStakePaused()
        external
        onlyRole(EXECUTOR_ROLE)
    {
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
    function getExchangeRate() public returns (uint256) {
        (, int256 beaconValidatorBalance, , uint256 updatedAt, ) = ethXFeed.latestRoundData();
        if(oracleLastUpdatedAt>=updatedAt) return exchangeRate;

        uint256 ELRewards = IExecutionLayerRewardContract(executionLayerRewardContract).withdrawELRewards();
        uint256 validatorCount = validatorRegistry.validatorCount();
        if(uint256(beaconValidatorBalance) > DEPOSIT_SIZE*validatorCount + prevBeaconChainReward){
            _distributeFee(uint256(beaconValidatorBalance), ELRewards, validatorCount);
        }
        bufferedEth += ELRewards;
        oracleLastUpdatedAt = updatedAt;
        totalTVL =
            bufferedEth +
            uint256(beaconValidatorBalance) +
            address(poolParameters[0].poolAddress).balance +
            address(poolParameters[1].poolAddress).balance;
        uint256 totalSupply = ethX.totalSupply();
        if (totalSupply == 0 || totalTVL == 0) {
            return 1 * DECIMALS;
        } else {
            exchangeRate = (totalTVL * DECIMALS) / totalSupply;
        }
        return exchangeRate;
    }

    /**
     * @dev Process user deposit, mints liquid tokens ethX based on exchange Rate
     * @param _referral address of referral.
     */
    function _deposit(address _referral) internal whenNotPaused {
        require(!isStakePaused, "Staking is paused");
        uint256 amount = msg.value;
        require(
            amount >= minDeposit && amount <= maxDeposit,
            "invalid stake amount"
        );
        exchangeRate = getExchangeRate();
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
        (bool ssvPoolSuccess, ) = (poolParameters[0].poolAddress).call{
            value: (amount * poolParameters[0].poolWeight) / 100
        }(abi.encodeWithSignature("receive()"));
        (bool staderPoolSuccess, ) = (poolParameters[1].poolAddress).call{
            value: (amount * poolParameters[1].poolWeight) / 100
        }(abi.encodeWithSignature("receive()"));
        require(ssvPoolSuccess, "SSV Pool ETH transfer failed");
        require(staderPoolSuccess, "Stader Pool ETH transfer failed");
        bufferedEth -= (amount);
        emit TransferredToSSVPool(
            poolParameters[0].poolAddress,
            (amount * poolParameters[0].poolWeight) / 100
        );
        emit TransferredToStaderPool(
            poolParameters[1].poolAddress,
            (amount * poolParameters[1].poolWeight) / 100
        );
    }

    /**
     * @notice fee distribution logic on rewards
     * @dev only run when chainlink oracle update beaconChain balance
     */
    function _distributeFee(uint256 _beaconValidatorBalance, uint256 _ELRewards, uint256 _validatorCount) internal{
        uint256 beaconChainRewards = _beaconValidatorBalance - DEPOSIT_SIZE*_validatorCount -prevBeaconChainReward ;
        prevBeaconChainReward = beaconChainRewards;
        uint256 totalRewards = beaconChainRewards + _ELRewards ;
        uint256 ethXMintedAsFees = (totalRewards * DECIMALS * feePercentage) / (exchangeRate *100) ;
        ethX.mint(staderTreasury, ethXMintedAsFees);
    }

    function _initialSetup() internal {
        minDeposit = 1;
        maxDeposit = 32 ether;
        feePercentage = 10;
        exchangeRate = 1 * DECIMALS;
    }


}
