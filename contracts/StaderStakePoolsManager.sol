// File: contracts/Stader.sol
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.2;

import "./EthX.sol";
import "./TimelockOwner.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 *  @title Liquid Staking Pool Implementation
 *  Stader is a non-custodial smart contract-based staking platform that helps you conveniently discover and access staking solutions.
 *  We are building key staking middleware infra for multiple PoS networks for retail crypto users, exchanges and custodians.
 */
contract StaderStakePoolsManager is TimelockOwner {
    using SafeMath for uint256;
    ETHX public ethX;
    uint256 public minDeposit;
    uint256 public maxDeposit;
    uint256 public totalTVL;
    uint256 public constant decimals = 10**18;
    uint256 public constant deposit_size = 32 ether;
    bool public isStakePaused;
    bool public _paused;
    address public staderStakePoolsManagerOwner;
    address payable[] public poolAddresses;
    uint256[] public poolWeights;

    // event emits after stake function
    event Deposited(address indexed sender, uint256 amount, address referral);

    /// event emits after transfer of ETh to a selected pool
    event TransferredtoPool(address indexed poolAddress);

    /// event emits after updating pool weights
    event updatedPoolWeights(uint256 ssspWeight, uint256 smspWeight);

    /// event emits after updating pool address
    event updatedPoolAddresses(address ssspAddress, address smspAddress);

    /// event emits after updating minDeposit value
    event updatedMinDeposit(uint256 amount);

    /// event emits after updating maxDeposit value
    event updatedMaxDeposit(uint256 amount);

    /// event emits after updating ethX address
    event updatedEthXAddress(address account);

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
     * @param _timelockOwner multi sig owner of the contract
     */
    function initialize(
        address _timelockOwner,
        ETHX _ethX,
        address payable _staderSSVStakePoolAddress,
        address payable _staderManagedStakePoolAddress,
        uint256 _staderSSVStakePoolWeight,
        uint256 _staderManagedStakePoolWeight
    ) public initializer checkZeroAddress(_timelockOwner) {
        TimelockOwner.initializeTimelockOwner(_timelockOwner);
        staderStakePoolsManagerOwner = msg.sender;
        ethX = _ethX;
        poolAddresses.push(_staderSSVStakePoolWeight);
        poolAddresses.push(_staderManagedStakePoolAddress);
        poolWeights.push(_staderSSVStakePoolWeight);
        poolWeights.push(_staderManagedStakePoolWeight);
        initialSetup();
    }

    function initialSetup() internal {
        minDeposit = 1;
        maxDeposit = 32 ether;
        totalTVL = 0;
        isStakePaused = false;
        _paused = false;
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

        uint256 exchangeRate = getExchangeRate();

        uint256 amountToSend = (amount * decimals) / exchangeRate;

        ethX.mint(msg.sender, amountToSend);

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
        poolAddresses[poolIndex].transfer(address(this).balance);
        emit TransferredtoPool(poolAddresses[poolIndex]);
    }

    /**
     * @notice update the pool to register validators
     * @dev update the pool weights
     */
    function updatePoolWeights(
        uint256 _staderSSVStakePoolWeight,
        uint256 _staderManagedStakePoolWeight
    ) external checkTimelockOwner {
        require(
            _staderSSVStakePoolWeight + _staderManagedStakePoolWeight == 1,
            "Invalid weights"
        );
        poolWeights[0] = _staderSSVStakePoolWeight;
        poolWeights[1] = _staderManagedStakePoolWeight;
        emit updatedPoolWeights(poolWeights[0],poolWeights[1]);
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
        checkTimelockOwner
    {
        poolAddresses[0] = _staderSSVStakePoolAddress;
        poolAddresses[1] = _staderManagedStakePoolAddress;
        emit updatedPoolAddresses(poolAddresses[0],poolAddresses[1]);
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
     * @dev update ethX address
     * @param _ethX ethX contract
     */
    function updateEthXAddress(ETHX _ethX)
        external
        checkZeroAddress(address(_ethX))
        checkOwner
    {
        ethX = _ethX;
        emit updatedEthXAddress(ethX);
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
        require(msg.data.length == 0, "NON_EMPTY_DATA");
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
