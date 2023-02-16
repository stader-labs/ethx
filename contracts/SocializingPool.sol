// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/ISocializingPool.sol';
import './interfaces/IPoolSelector.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract SocializingPool is ISocializingPool, Initializable, AccessControlUpgradeable {
    IPoolSelector public poolHelper;
    IStaderStakePoolManager public staderStakePoolManager;
    address public staderTreasury;
    uint256 public feePercentage;
    uint256 public totalELRewardsCollected;

    bytes32 public constant SOCIALIZE_POOL_OWNER = keccak256('SOCIALIZE_POOL_OWNER');
    bytes32 public constant REWARD_DISTRIBUTOR = keccak256('REWARD_DISTRIBUTOR');

    function initialize(
        address _adminOwner,
        address _staderStakePoolManager,
        address _staderTreasury
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_staderStakePoolManager);
        Address.checkNonZeroAddress(_staderTreasury);
        __AccessControl_init_unchained();
        staderStakePoolManager = IStaderStakePoolManager(_staderStakePoolManager);
        staderTreasury = _staderTreasury;
        feePercentage = 10;
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
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
    // function distributeELRewardFee() external onlyRole(REWARD_DISTRIBUTOR) {
    //     uint256 ELRewards = address(this).balance;
    //     require(ELRewards > 0, 'not enough execution layer rewards');
    //     totalELRewardsCollected += ELRewards;
    //     uint256 totalELFee = (ELRewards * feePercentage) / 100;
    //     uint256 staderELFee = totalELFee / 2;
    //     uint256 totalOperatorELFee;
    //     uint256 totalValidatorRegistered = staderValidatorRegistry.registeredValidatorCount();
    //     require(totalValidatorRegistered > 0, 'No active validator on beacon chain');
    //     uint256 operatorCount = staderOperatorRegistry.getOperatorCount();
    //     for (uint256 index = 0; index < operatorCount; ++index) {
    //         address nodeOperator = staderOperatorRegistry.operatorByOperatorId(index);
    //         (, , address operatorRewardAddress, , , , uint256 activeValidatorCount, ) = staderOperatorRegistry
    //             .operatorRegistry(nodeOperator);
    //         if (activeValidatorCount > 0) {
    //             uint256 operatorELFee = ((totalELFee - staderELFee) * activeValidatorCount) / totalValidatorRegistered;
    //             totalOperatorELFee += operatorELFee;

    //             //slither-disable-next-line arbitrary-send-eth
    //             staderStakePoolManager.deposit{value: operatorELFee}(operatorRewardAddress);
    //         }
    //     }
    //     staderELFee = totalELFee - totalOperatorELFee;

    //     //slither-disable-next-line arbitrary-send-eth
    //     staderStakePoolManager.deposit{value: staderELFee}(staderTreasury);

    //     //slither-disable-next-line arbitrary-send-eth
    //     staderStakePoolManager.receiveExecutionLayerRewards{value: address(this).balance}();
    // }

    function updatePoolSelector(address _poolSelector) external onlyRole(SOCIALIZE_POOL_OWNER) {
        Address.checkNonZeroAddress(_poolSelector);
        poolHelper = IPoolSelector(_poolSelector);
    }

    /**
     * @dev update stader pool manager address
     * @param _staderStakePoolManager staderPoolManager address
     */
    function updateStaderStakePoolManager(address _staderStakePoolManager) external onlyRole(SOCIALIZE_POOL_OWNER) {
        Address.checkNonZeroAddress(_staderStakePoolManager);
        staderStakePoolManager = IStaderStakePoolManager(_staderStakePoolManager);
        emit UpdatedStaderPoolManager(_staderStakePoolManager);
    }

    /**
     * @dev update stader treasury address
     * @param _staderTreasury staderTreasury address
     */
    function updateStaderTreasury(address _staderTreasury) external onlyRole(SOCIALIZE_POOL_OWNER) {
        Address.checkNonZeroAddress(_staderTreasury);
        staderTreasury = _staderTreasury;
        emit UpdatedStaderTreasury(staderTreasury);
    }

    /**
     * @dev update stader EL reward fee percentage
     * @param _feePercentage new fee percentage
     */
    function updateFeePercentage(uint256 _feePercentage) external onlyRole(SOCIALIZE_POOL_OWNER) {
        feePercentage = _feePercentage;
        emit UpdatedFeePercentage(feePercentage);
    }
}
