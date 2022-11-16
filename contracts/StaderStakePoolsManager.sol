// File: contracts/StaderStakePoolsManager.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./EthX.sol";
import "./TimelockOwner.sol";
import "./interfaces/IStaderValidatorRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


/**
 *  @title Liquid Staking Pool Implementation
 *  Stader is a non-custodial smart contract-based staking platform that helps you conveniently discover and access staking solutions.
 *  We are building key staking middleware infra for multiple PoS networks for retail crypto users, exchanges and custodians.
 */
contract StaderStakePoolsManager is TimeLockOwner {
    using SafeMath for uint256;
    ETHX public ethX;
    AggregatorV3Interface internal ethXFeed;
    uint256 public minDeposit;
    uint256 public maxDeposit;
    uint256 public constant decimals = 10**18;
    uint256 public constant deposit_size = 32 ether;
    bool public isStakePaused;
    bool public _paused;
    address public staderStakePoolsManagerOwner;
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
    event TransferredToPool(address indexed poolAddress);

    /// event emits after updating pool weights
    event updatedPoolWeights(
        uint256 staderSSVStakePoolWeight,
        uint256 staderManagedStakePoolWeight
    );

    /// event emits after updating pool address
    event updatedPoolAddresses(
        address staderSSVStakePoolAddress,
        address staderManagedStakePoolAddress
    );

    /// event emits after updating minDeposit value
    event updatedMinDeposit(uint256 amount);

    /// event emits after updating maxDeposit value
    event updatedMaxDeposit(uint256 amount);

    /// event emits after updating ethX address
    event updatedEthXAddress(address account);

    /// event emits after updating ethX feed
    event updatedEthXFeed(address account);

    /// event emits after updating staderStakePoolsManagerOwner address
    event updatedStaderStakePoolsManagerOwner(address account);

    // Emit when the pause is triggered by `account`.
    event Paused(address account);

    // Emit when the pause is lifted by `account`.
    event Unpaused(address account);

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     * The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     * The contract must be paused.
     */
    modifier whenPaused() {
        require(_paused, "Pausable: not paused");
        _;
    }

    /// @notice check for admin role
    modifier checkOwner() {
        require(
            msg.sender == staderStakePoolsManagerOwner,
            "Caller is not an Admin"
        );
        _;
    }

    /**
     * @dev Stader initialized with following variables
     * @param _ethX ethX contract
     * @param _timeLockOwner multi sig owner of the contract
     * @param _staderSSVStakePoolAddress stader SSV Managed Pool, validator are assigned to operator through SSV
     * @param _staderManagedStakePoolAddress validator are assigned to operator, managed by stader
     * @param _staderSSVStakePoolWeight weight of stader SSV pool, if it is 1 then validator gets operator via SSV
     * @param _staderManagedStakePoolWeight weight of stader managed pool, if it is 1 then validator gets stader managed operator
     */
    function initialize(
        address _timeLockOwner,
        ETHX _ethX,
        address  _staderSSVStakePoolAddress,
        address  _staderManagedStakePoolAddress,
        uint256 _staderSSVStakePoolWeight,
        uint256 _staderManagedStakePoolWeight
    )
        public
        initializer
        checkZeroAddress(_timeLockOwner)
        checkZeroAddress(address(_ethX))
        checkZeroAddress(address(_staderSSVStakePoolAddress))
        checkZeroAddress(address(_staderManagedStakePoolAddress))
    {
        require(
            _staderSSVStakePoolWeight + _staderManagedStakePoolWeight == 1,
            "Invalid pool weights"
        );
        TimeLockOwner.initializeTimeLockOwner(_timeLockOwner);
        staderStakePoolsManagerOwner = msg.sender;
        ethX = _ethX;
        ethXFeed = AggregatorV3Interface(0xa81FE04086865e63E12dD3776978E49DEEa2ea4e);
        poolAddresses.push(_staderSSVStakePoolAddress);
        poolAddresses.push(_staderManagedStakePoolAddress);
        poolWeights.push(_staderSSVStakePoolWeight);
        poolWeights.push(_staderManagedStakePoolWeight);
        initialSetup();
    }

    function initialSetup() internal {
        minDeposit = 1;
        maxDeposit = 32 ether;
        bufferedEth =0;
        isStakePaused = false;
        _paused = false;
        exchangeRate = 1 * decimals;
        totalTVL = 0;
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
            "Stake amount must be within valid range"
        );
        uint256 amountToSend = (amount * decimals) / exchangeRate;
        ethX.mint(msg.sender, amountToSend);
        bufferedEth = bufferedEth+ amount;
        emit Deposited(msg.sender, amount, _referral);
    }

    /**
     * @notice check for eth balance of the contract and transfer to a pool if balance crosses 32 eth
     * @dev Anyone can call this function, if balance more than 32 eth, will transfer to one of the pool
     */
    function stakeEpoch() external {
        require(
            address(this).balance > 32 ether,
            "Not enough ETH for transferring to a Pool"
        );
        selectPool();
    }

    /**
     * @notice selecting a pool from SSSP and SMSP
     * @dev select a pool based on poolWeight
     */
    function selectPool() internal {
        uint256 poolIndex = poolWeights[0] > poolWeights[1] ? 0 : 1;
        uint256 numberOfDeposits = bufferedEth/deposit_size ;
        (bool success, ) = (poolAddresses[poolIndex]).call{value: numberOfDeposits* deposit_size}(
            abi.encodeWithSignature('receiveEthFromPoolManager()'));
        // (bool success, ) = (poolAddresses[poolIndex]).receiveEthFromPoolManager(){value: 32 ether};
        if (!success) revert("sending Eth to pool Failed");
        bufferedEth = bufferedEth-(numberOfDeposits* deposit_size);
        emit TransferredToPool(poolAddresses[poolIndex]);
    }

    /**
     * @notice calculation of exchange Rate
     * @dev exchange rate determines of amount of ethX receive on staking eth
     */
    function updateExchangeRate() public returns(uint256){
        (,int256 beaconValidatorBalance,,,) = ethXFeed.latestRoundData() ;
        totalTVL = bufferedEth + uint256(beaconValidatorBalance)+ address(poolAddresses[0]).balance+ address(poolAddresses[1]).balance;
        uint256 totalSupply = ethX.totalSupply();
        if (totalSupply == 0 || totalTVL == 0) {
            return 1 * decimals;
        } else {
            exchangeRate = (totalTVL * decimals) / totalSupply;
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
            _staderSSVStakePoolWeight + _staderManagedStakePoolWeight == 1,
            "Invalid weights"
        );
        poolWeights[0] = _staderSSVStakePoolWeight;
        poolWeights[1] = _staderManagedStakePoolWeight;
        emit updatedPoolWeights(poolWeights[0], poolWeights[1]);
    }

    /**
     * @notice update the pool to register validators
     * @dev update the pool weights
     */
    function updatePoolAddresses(
        address payable _staderSSVStakePoolAddress,
        address payable _staderManagedStakePoolAddress
    )
        external
        checkZeroAddress(_staderSSVStakePoolAddress)
        checkZeroAddress(_staderManagedStakePoolAddress)
        checkTimeLockOwner
    {
        poolAddresses[0] = _staderSSVStakePoolAddress;
        poolAddresses[1] = _staderManagedStakePoolAddress;
        emit updatedPoolAddresses(poolAddresses[0], poolAddresses[1]);
    }

    /**
     * @dev update the minimum stake amount
     * @param _minDeposit minimum deposit value
     */
    function updateMinDeposit(uint256 _minDeposit) external checkOwner {
        require(_minDeposit > 0, "minimum deposit should be greater than 0");
        minDeposit = _minDeposit;
        emit updatedMinDeposit(minDeposit);
    }

    /**
     * @dev update the maximum stake amount
     * @param _maxDeposit maximum deposit value
     */
    function updateMaxDeposit(uint256 _maxDeposit) external checkOwner {
        require(
            _maxDeposit > minDeposit,
            "maximum deposit should be greater than minimum deposit"
        );
        maxDeposit = _maxDeposit;
        emit updatedMaxDeposit(maxDeposit);
    }

    /**
     * @dev update ethX feed
     * @param _ethXFeed ethX contract
     */
    function updateEthXFeed(AggregatorV3Interface _ethXFeed)
        external
        checkZeroAddress(address(_ethXFeed))
        checkOwner
    {
        ethXFeed = _ethXFeed;
        emit updatedEthXFeed(address(_ethXFeed));
    }

        /**
     * @dev update ethX address
     * @param _ethX ethX contract
     */
    function updateEthXAddress(ETHX _ethX)
        external
        checkZeroAddress(address(_ethX))
        checkOwner
    {
        ethX = _ethX;
        emit updatedEthXAddress(address(ethX));
    }

    /**
     * @dev update StaderStakePoolsManagerOwner
     */
    function updateStaderStakePoolsManagerOwner(address _newOwner)
        external
        checkOwner
        checkZeroAddress(_newOwner)
    {
        staderStakePoolsManagerOwner = _newOwner;
        emit updatedStaderStakePoolsManagerOwner(staderStakePoolsManagerOwner);
    }

    /**
     * @dev Triggers stopped state.
     * - The contract must not be paused.
     */
    function _pause() external checkOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev Returns to normal state.
     * - The contract must be paused.
     */
    function _unpause() external checkOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
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
