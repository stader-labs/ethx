// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/AddressLib.sol';
import './library/ValidatorStatus.sol';

import './interfaces/IPenalty.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/INodeRegistry.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IValidatorWithdrawalVault.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

contract ValidatorWithdrawalVault is
    IValidatorWithdrawalVault,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using Math for uint256;
    uint8 public poolId;
    IStaderConfig public staderConfig;
    uint256 public validatorId;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint8 _poolId,
        address _staderConfig,
        uint256 _validatorId
    ) external initializer {
        AddressLib.checkNonZeroAddress(_staderConfig);

        __AccessControl_init_unchained();
        __ReentrancyGuard_init();

        staderConfig = IStaderConfig(_staderConfig);
        poolId = _poolId;
        validatorId = _validatorId;
        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    // Allows the contract to receive ETH
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function distributeRewards() external nonReentrant {
        uint256 totalRewards = address(this).balance;

        // TODO: in below condition, let staderManager handle it, impl to byPass below revert for staderManager
        if (totalRewards > staderConfig.getRewardsThreshold()) {
            emit DistributeRewardFailed(totalRewards, staderConfig.getRewardsThreshold());
            revert InvalidRewardAmount();
        }

        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = _calculateRewardShare(totalRewards);

        // Distribute rewards
        IStaderStakePoolManager(staderConfig.getStakePoolManager()).receiveWithdrawVaultUserShare{value: userShare}();
        _sendValue(getNodeRecipient(), operatorShare);
        _sendValue(payable(staderConfig.getStaderTreasury()), protocolShare);
        emit DistributedRewards(userShare, operatorShare, protocolShare);
    }

    function _calculateRewardShare(uint256 _totalRewards)
        internal
        view
        returns (
            uint256 userShare,
            uint256 operatorShare,
            uint256 protocolShare
        )
    {
        uint256 TOTAL_STAKED_ETH = staderConfig.getStakedEthPerNode();
        uint256 collateralETH = getCollateralETH();
        uint256 usersETH = TOTAL_STAKED_ETH - collateralETH;
        uint256 protocolFeeBps = getProtocolFeeBps();
        uint256 operatorFeeBps = getOperatorFeeBps();

        uint256 _userShareBeforeCommision = (_totalRewards * usersETH) / TOTAL_STAKED_ETH;

        protocolShare = (protocolFeeBps * _userShareBeforeCommision) / 10000;

        operatorShare = (_totalRewards * collateralETH) / TOTAL_STAKED_ETH;
        operatorShare += (operatorFeeBps * _userShareBeforeCommision) / 10000;

        userShare = _totalRewards - protocolShare - operatorShare;
    }

    function settleFunds() external nonReentrant {
        if (!isWithdrawnValidator()) {
            revert ValidatorNotWithdrawn();
        }
        (uint256 userShare_prelim, uint256 operatorShare, uint256 protocolShare) = _calculateValidatorWithdrawalShare();

        uint256 penaltyAmount = getPenaltyAmount();
        //TODO liquidate SD if operatorShare < penaltyAmount

        penaltyAmount = Math.min(penaltyAmount, operatorShare);
        uint256 userShare = userShare_prelim + penaltyAmount;
        operatorShare = operatorShare - penaltyAmount;
        // Final settlement
        IStaderStakePoolManager(staderConfig.getStakePoolManager()).receiveWithdrawVaultUserShare{value: userShare}();
        _sendValue(getNodeRecipient(), operatorShare);
        _sendValue(payable(staderConfig.getStaderTreasury()), protocolShare);
        emit SettledFunds(userShare, operatorShare, protocolShare);
    }

    //update the address of staderConfig
    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        AddressLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    function _calculateValidatorWithdrawalShare()
        internal
        view
        returns (
            uint256 _userShare,
            uint256 _operatorShare,
            uint256 _protocolShare
        )
    {
        uint256 TOTAL_STAKED_ETH = staderConfig.getStakedEthPerNode();
        uint256 collateralETH = getCollateralETH(); // 0, incase of permissioned NOs
        uint256 usersETH = TOTAL_STAKED_ETH - collateralETH;
        uint256 contractBalance = address(this).balance;

        uint256 totalRewards;

        if (contractBalance <= usersETH) {
            _userShare = contractBalance;
            return (_userShare, _operatorShare, _protocolShare);
        } else if (contractBalance <= TOTAL_STAKED_ETH) {
            _userShare = usersETH;
            _operatorShare = contractBalance - _userShare;
            return (_userShare, _operatorShare, _protocolShare);
        } else {
            totalRewards = contractBalance - TOTAL_STAKED_ETH;
            _operatorShare = collateralETH;
            _userShare = usersETH;
        }

        (uint256 userReward, uint256 operatorReward, uint256 protocolReward) = _calculateRewardShare(totalRewards);
        _userShare += userReward;
        _operatorShare += operatorReward;
        _protocolShare += protocolReward;
    }

    function _sendValue(address payable _recipient, uint256 _amount) internal {
        if (address(this).balance < _amount) {
            revert InsufficientBalance();
        }

        //slither-disable-next-line arbitrary-send-eth
        if (_amount > 0) {
            (bool success, ) = _recipient.call{value: _amount}('');
            if (!success) {
                revert ETHTransferFailed(_recipient, _amount);
            }
        }
    }

    // getters

    function getProtocolFeeBps() internal view returns (uint256) {
        return IPoolFactory(staderConfig.getPoolFactory()).getProtocolFee(poolId);
    }

    // should return 0, for permissioned NOs
    function getOperatorFeeBps() internal view returns (uint256) {
        return IPoolFactory(staderConfig.getPoolFactory()).getOperatorFee(poolId);
    }

    function getCollateralETH() private view returns (uint256) {
        return IPoolFactory(staderConfig.getPoolFactory()).getCollateralETH(poolId);
    }

    function getNodeRecipient() private view returns (address payable) {
        address nodeRegistry = IPoolFactory(staderConfig.getPoolFactory()).getNodeRegistry(poolId);
        (, , , , , uint256 operatorId, , ) = INodeRegistry(nodeRegistry).validatorRegistry(validatorId);
        (, , , address payable operatorRewardAddress, ) = INodeRegistry(nodeRegistry).operatorStructById(operatorId);
        return operatorRewardAddress;
    }

    function getPenaltyAmount() private returns (uint256) {
        address nodeRegistry = IPoolFactory(staderConfig.getPoolFactory()).getNodeRegistry(poolId);
        (, bytes memory pubkey, , , , , , ) = INodeRegistry(nodeRegistry).validatorRegistry(validatorId);
        return IPenalty(staderConfig.getPenaltyContract()).calculatePenalty(pubkey);
    }

    function isWithdrawnValidator() private view returns (bool) {
        address nodeRegistry = IPoolFactory(staderConfig.getPoolFactory()).getNodeRegistry(poolId);
        (ValidatorStatus status, , , , , , , ) = INodeRegistry(nodeRegistry).validatorRegistry(validatorId);
        return status == ValidatorStatus.WITHDRAWN;
    }
}
