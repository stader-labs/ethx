// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./EthX.sol";
import "./TimelockOwner.sol";
import "./interfaces/IStaderValidatorRegistry.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/**
 *  @title Liquid Staking Pool Implementation
 *  Stader is a non-custodial smart contract-based staking platform
 *  that helps you conveniently discover and access staking solutions.
 *  We are building key staking middleware infra for multiple PoS networks
 * for retail crypto users, exchanges and custodians.
 */
contract StaderStakePoolsManager is TimeLockOwner, PausableUpgradeable {

    uint256 public constant DECIMALS = 10**18;
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    ETHX public ethX;
    AggregatorV3Interface internal ethXFeed;
    uint256 public minDeposit;
    uint256 public maxDeposit;
    bool public isStakePaused;
    bool public _paused;
    address[] public poolAddresses;
    uint256[] public poolWeights;
    uint256 public bufferedEth;
    uint256 public prevBeaconValidatorBalance;
    uint256 public prevBeaconValidatorCount;
    uint256 public exchangeRate;
    uint256 public totalTVL;

    // event emits after stake function
    event Deposited(address indexed sender, uint256 amount, address referral);

    /// event emits after transfer of ETh to a selected pool
    event TransferredToSSVPool(address indexed poolAddress, uint256 amount);
    /// event emits after transfer of ETh to a selected pool
    event TransferredToStaderPool(address indexed poolAddress, uint256 amount);

    /// event emits after updating pool weights
    event UpdatedPoolWeights(
        uint256 staderSSVStakePoolWeight,
        uint256 staderManagedStakePoolWeight
    );

    /// event emits after updating ssv stake pool address
    event UpdatedSSVStakePoolAddress(address ssvStakePool);

    /// event emits after updating stader stake pool address
    event UpdatedStaderStakePoolAddress(address staderStakePool);

    /// event emits after updating minDeposit value
    event UpdatedMinDeposit(uint256 amount);

    /// event emits after updating maxDeposit value
    event UpdatedMaxDeposit(uint256 amount);

    /// event emits after updating ethX address
    event UpdatedEthXAddress(address account);

    /// event emits after updating ethX feed
    event UpdatedEthXFeed(address account);

    /**
     * @dev Stader initialized with following variables
     * @param _ethX ethX contract
     * @param _timeLockOwner multi sig owner of the contract
     * @param _staderSSVStakePoolAddress stader SSV Managed Pool, validator are assigned to operator through SSV
     * @param _staderManagedStakePoolAddress validator are assigned to operator, managed by stader
     * @param _staderSSVStakePoolWeight weight of stader SSV pool, if it is 1 then validator gets operator via SSV
     * @param _staderManagedStakePoolWeight weight of stader managed pool
     */
    function initialize(
        address _timeLockOwner,
        ETHX _ethX,
        address _ethXFeed,
        address _staderSSVStakePoolAddress,
        address _staderManagedStakePoolAddress,
        uint256 _staderSSVStakePoolWeight,
        uint256 _staderManagedStakePoolWeight
    )
        external
        initializer
        checkZeroAddress(_timeLockOwner)
        checkZeroAddress(address(_ethX))
        checkZeroAddress(address(_ethXFeed))
        checkZeroAddress(address(_staderSSVStakePoolAddress))
        checkZeroAddress(address(_staderManagedStakePoolAddress))
    {
        require(
            _staderSSVStakePoolWeight + _staderManagedStakePoolWeight == 100,
            "Invalid pool weights"
        );
        __Ownable_init_unchained();
        TimeLockOwner.initializeTimeLockOwner(_timeLockOwner);
        ethX = _ethX;
        ethXFeed = AggregatorV3Interface(_ethXFeed);
        poolAddresses.push(_staderSSVStakePoolAddress);
        poolAddresses.push(_staderManagedStakePoolAddress);
        poolWeights.push(_staderSSVStakePoolWeight);
        poolWeights.push(_staderManagedStakePoolWeight);
        initialSetup();
    }

    function initialSetup() internal {
        minDeposit = 1;
        maxDeposit = 32 ether;
        exchangeRate = 1 * DECIMALS;
    }

    /**
     * @notice Alternate way to send funds to pool apart from fallback function
     * @dev user deposit their funds with an optional _referral parameter
     */
    function deposit(address _referral) external payable {
        _deposit(_referral);
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
        uint256 amountToSend = (amount * DECIMALS) / exchangeRate;
        bufferedEth += amount;
        ethX.mint(msg.sender, amountToSend);
        if(address(this).balance >= 32 ether){
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
        uint256 amount = numberOfDeposits*DEPOSIT_SIZE;
        (bool ssvPoolSuccess, ) = (poolAddresses[0]).call{
            value: (amount*poolWeights[0])/100
        }(abi.encodeWithSignature("receive()"));
        (bool staderPoolSuccess, ) = (poolAddresses[1]).call{
            value: (amount*poolWeights[1])/100
        }(abi.encodeWithSignature("receive()"));
        require(ssvPoolSuccess, "SSV Pool ETH transfer failed");
        require(staderPoolSuccess, "Stader Pool ETH transfer failed");
        bufferedEth -= (amount);
        emit TransferredToSSVPool(poolAddresses[0], amount*(poolWeights[0]/100));
        emit TransferredToStaderPool(poolAddresses[1], amount*(poolWeights[1]/100));
    }

    /**
     * @notice calculation of exchange Rate
     * @dev exchange rate determines of amount of ethX receive on staking eth
     */
    function updateExchangeRate() public returns (uint256) {
        (, int256 beaconValidatorBalance, , , ) = ethXFeed.latestRoundData();
        totalTVL =
            bufferedEth +
            uint256(beaconValidatorBalance) +
            address(poolAddresses[0]).balance +
            address(poolAddresses[1]).balance;
        uint256 totalSupply = ethX.totalSupply();
        if (totalSupply == 0 || totalTVL == 0) {
            return 1 * DECIMALS;
        } else {
            exchangeRate = (totalTVL * DECIMALS) / totalSupply;
        }
        return exchangeRate;
    }

    /**
     * @notice update the pool to register validators
     * @dev update the pool weights
     */
    function updatePoolWeights(
        uint256 _staderSSVStakePoolWeight,
        uint256 _staderManagedStakePoolWeight
    ) external checkTimeLockOwner {
        require(
            _staderSSVStakePoolWeight + _staderManagedStakePoolWeight == 100,
            "Invalid weights"
        );
        poolWeights[0] = _staderSSVStakePoolWeight;
        poolWeights[1] = _staderManagedStakePoolWeight;
        emit UpdatedPoolWeights(poolWeights[0], poolWeights[1]);
    }

    /**
     * @notice update the pool to register validators
     * @dev update the pool weights
     */
    function updateSSVStakePoolAddresses(
        address payable _staderSSVStakePoolAddress
    )
        external
        checkZeroAddress(_staderSSVStakePoolAddress)
        checkTimeLockOwner
    {
        poolAddresses[0] = _staderSSVStakePoolAddress;
        emit UpdatedSSVStakePoolAddress(poolAddresses[0]);
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
        checkTimeLockOwner
    {
        poolAddresses[1] = _staderManagedStakePoolAddress;
        emit UpdatedStaderStakePoolAddress(poolAddresses[1]);
    }

    /**
     * @dev update the minimum stake amount
     * @param _minDeposit minimum deposit value
     */
    function updateMinDeposit(uint256 _minDeposit) external  {
        require(_minDeposit > 0, "invalid minDeposit value");
        minDeposit = _minDeposit;
        emit UpdatedMinDeposit(minDeposit);
    }

    /**
     * @dev update the maximum stake amount
     * @param _maxDeposit maximum deposit value
     */
    function updateMaxDeposit(uint256 _maxDeposit) external checkTimeLockOwner {
        require(
            _maxDeposit > minDeposit,
            "invalid maxDeposit value"
        );
        maxDeposit = _maxDeposit;
        emit UpdatedMaxDeposit(maxDeposit);
    }

    /**
     * @dev update ethX feed
     * @param _ethXFeed ethX contract
     */
    function updateEthXFeed(AggregatorV3Interface _ethXFeed)
        external
        checkZeroAddress(address(_ethXFeed))
        checkTimeLockOwner
    {
        ethXFeed = _ethXFeed;
        emit UpdatedEthXFeed(address(_ethXFeed));
    }

    /**
     * @dev update ethX address
     * @param _ethX ethX contract
     */
    function updateEthXAddress(ETHX _ethX)
        external
        checkZeroAddress(address(_ethX))
        checkTimeLockOwner
    {
        ethX = _ethX;
        emit UpdatedEthXAddress(address(ethX));
    }

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
     * @notice Send funds to the pool
     * @dev Users are able to deposit their funds by transacting to the receive function.
     */
    receive() external payable {
        require(msg.value == 0, "Invalid Amount");
        _deposit(address(0));
    }
}
