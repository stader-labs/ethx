// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/ISocializingPoolContract.sol';
import './interfaces/IStaderOperatorRegistry.sol';
import './interfaces/IStaderValidatorRegistry.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract SocializingPoolContract is ISocializingPoolContract, Initializable, AccessControlUpgradeable {
    IStaderValidatorRegistry public staderValidatorRegistry;
    IStaderOperatorRegistry public staderOperatorRegistry;
    IStaderStakePoolManager public staderStakePoolManager;
    address public staderTreasury;
    uint256 public feePercentage;
    uint256 public totalELRewardsCollected;

    bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');
    bytes32 public constant REWARD_DISTRIBUTOR = keccak256('REWARD_DISTRIBUTOR');

    /// @notice zero address check modifier
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    function initialize(
        address _staderOperatorRegistry,
        address _staderValidatorRegistry,
        address _staderStakePoolManager,
        address _elRewardContractOwner,
        address _staderTreasury
    )
        external
        initializer
        checkZeroAddress(_staderOperatorRegistry)
        checkZeroAddress(_staderValidatorRegistry)
        checkZeroAddress(_staderStakePoolManager)
        checkZeroAddress(_elRewardContractOwner)
        checkZeroAddress(_staderTreasury)
    {
        __AccessControl_init_unchained();
        staderOperatorRegistry = IStaderOperatorRegistry(_staderOperatorRegistry);
        staderValidatorRegistry = IStaderValidatorRegistry(_staderValidatorRegistry);
        staderStakePoolManager = IStaderStakePoolManager(_staderStakePoolManager);
        staderTreasury = _staderTreasury;
        feePercentage = 10;
        _grantRole(ADMIN_ROLE, _elRewardContractOwner);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev execution layer rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.value);
    }

    /**
     * @notice fee distribution logic on execution layer rewards
     * @dev run once in 24 hour
     */
    function distributeELRewardFee() external onlyRole(REWARD_DISTRIBUTOR) {
        totalELRewardsCollected += address(this).balance;
        uint256 ELRewards = address(this).balance;
        uint256 totalELFee = (ELRewards * feePercentage) / 100;
        uint256 staderELFee = totalELFee / 2;
        uint256 totalOperatorELFee;
        uint256 totalValidatorRegistered = staderValidatorRegistry.registeredValidatorCount();
        uint256 operatorCount = staderOperatorRegistry.operatorCount();
        for (uint256 index = 0; index < operatorCount; index++) {
            (address operatorRewardAddress, , , , uint256 activeValidatorCount, ) = staderOperatorRegistry
                .operatorRegistry(index);
            uint256 operatorELFee = ((totalELFee - staderELFee) * activeValidatorCount) / totalValidatorRegistered;
            totalOperatorELFee += operatorELFee;

            //slither-disable-next-line arbitrary-send-eth
            staderStakePoolManager.deposit{value: operatorELFee}(operatorRewardAddress);
        }
        staderELFee = totalELFee - totalOperatorELFee;

        //slither-disable-next-line arbitrary-send-eth
        staderStakePoolManager.deposit{value: staderELFee}(staderTreasury);

        //slither-disable-next-line arbitrary-send-eth
        staderStakePoolManager.receiveExecutionLayerRewards{value: address(this).balance}();
    }

    /**
     * @dev update stader pool manager address
     * @param _staderStakePoolManager staderPoolManager address
     */
    function updateStaderStakePoolManager(address _staderStakePoolManager)
        external
        onlyRole(ADMIN_ROLE)
        checkZeroAddress(_staderStakePoolManager)
    {
        staderStakePoolManager = IStaderStakePoolManager(_staderStakePoolManager);
        emit UpdatedStaderPoolManager(_staderStakePoolManager);
    }

    /**
     * @dev update stader treasury address
     * @param _staderTreasury staderTreasury address
     */
    function updateStaderTreasury(address _staderTreasury)
        external
        checkZeroAddress(_staderTreasury)
        onlyRole(ADMIN_ROLE)
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
        onlyRole(ADMIN_ROLE)
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
        onlyRole(ADMIN_ROLE)
    {
        staderOperatorRegistry = IStaderOperatorRegistry(_staderOperatorRegistry);
        emit UpdatedStaderOperatorRegistry(address(staderOperatorRegistry));
    }

    /**
     * @dev update stader EL reward fee percentage
     * @param _feePercentage new fee percentage
     */
    function updateFeePercentage(uint256 _feePercentage) external onlyRole(ADMIN_ROLE) {
        feePercentage = _feePercentage;
        emit UpdatedFeePercentage(feePercentage);
    }
}
