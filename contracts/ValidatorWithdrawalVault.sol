// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/AddressLib.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import './interfaces/IValidatorWithdrawalVault.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/IPenalty.sol';
import './interfaces/INodeRegistry.sol';

contract ValidatorWithdrawalVault is
    IValidatorWithdrawalVault,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint8 public poolId;
    IStaderConfig public staderConfig;
    address payable public nodeRecipient;
    uint256 public validatorId;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint8 _poolId,
        address _staderConfig,
        //TODO sanjay as we _validatorId, _nodeRecipient becomes semi-redundant here
        address payable _nodeRecipient,
        uint256 _validatorId
    ) external initializer {
        AddressLib.checkNonZeroAddress(_staderConfig);
        AddressLib.checkNonZeroAddress(_nodeRecipient);

        __AccessControl_init_unchained();
        __ReentrancyGuard_init();

        staderConfig = IStaderConfig(_staderConfig);
        nodeRecipient = _nodeRecipient;
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
        _sendValue(nodeRecipient, operatorShare);
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
        if (msg.sender != IPoolFactory(staderConfig.getPoolFactory()).getNodeRegistry(poolId))
            revert CallerNotNodeRegistry();
        (uint256 userShare_prelim, uint256 operatorShare, uint256 protocolShare) = _calculateValidatorWithdrawalShare();

        uint256 penaltyAmount = getPenaltyAmount();
        uint256 userShare = userShare_prelim + _min(penaltyAmount, operatorShare);

        //TODO liquidate SD if operatorShare < penaltyAmount
        operatorShare = operatorShare > penaltyAmount ? operatorShare - penaltyAmount : 0;
        // Final settlement
        IStaderStakePoolManager(staderConfig.getStakePoolManager()).receiveWithdrawVaultUserShare{value: userShare}();
        _sendValue(nodeRecipient, operatorShare);
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
        if (address(this).balance < _amount) revert InsufficientBalance();

        //slither-disable-next-line arbitrary-send-eth
        if (_amount > 0) {
            (bool success, ) = _recipient.call{value: _amount}('');
            if (!success) revert TransferFailed();
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

    function getPenaltyAmount() private returns (uint256) {
        address nodeRegistry = IPoolFactory(staderConfig.getPoolFactory()).getNodeRegistry(poolId);
        (, bytes memory pubkey, , , , , , , ) = INodeRegistry(nodeRegistry).validatorRegistry(validatorId);
        return IPenalty(staderConfig.getPenaltyContract()).calculatePenalty(pubkey);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
