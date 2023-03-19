// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

import './interfaces/IValidatorWithdrawVault.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/IStaderConfig.sol';

contract ValidatorWithdrawVault is
    IValidatorWithdrawVault,
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant STADER_NODE_REGISTRY_CONTRACT = keccak256('STADER_NODE_REGISTRY_CONTRACT');
    IStaderConfig staderConfig;
    uint8 public poolId;
    address payable public nodeRecipient;

    // TODO: update params where this is deployed
    function initialize(
        address _admin,
        address _staderConfig,
        address payable _nodeRecipient,
        uint8 _poolId
    ) external initializer {
        Address.checkNonZeroAddress(_admin);
        Address.checkNonZeroAddress(_staderConfig);
        Address.checkNonZeroAddress(_nodeRecipient);

        __AccessControl_init_unchained();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        nodeRecipient = _nodeRecipient;
        poolId = _poolId;
        staderConfig = IStaderConfig(_staderConfig);
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev skimmed rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function distributeRewards() external nonReentrant {
        uint256 totalRewards = address(this).balance;

        // TODO: in below condition, let staderManager handle it, impl to byPass below revert for staderManager
        if (totalRewards > staderConfig.rewardThreshold()) {
            emit DistributeRewardFailed(totalRewards, staderConfig.rewardThreshold());
            revert InvalidRewardAmount();
        }

        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = _calculateRewardShare(totalRewards);

        // Distribute rewards
        IStaderStakePoolManager(staderConfig.stakePoolManager()).receiveWithdrawVaultUserShare{value: userShare}();
        _sendValue(nodeRecipient, operatorShare);
        _sendValue(payable(staderConfig.treasury()), protocolShare);
    }

    // TODO: add penalty changes
    // TODO: change percent to fee and 100 to 10_000
    function _calculateRewardShare(uint256 _totalRewards)
        internal
        view
        returns (
            uint256 _userShare,
            uint256 _operatorShare,
            uint256 _protocolShare
        )
    {
        uint256 TOTAL_STAKED_ETH = staderConfig.totalStakedEth();
        uint256 collateralETH = getCollateralETH();
        uint256 usersETH = TOTAL_STAKED_ETH - collateralETH;
        uint256 protocolFeePercent = getProtocolFeePercent();
        uint256 operatorFeePercent = getOperatorFeePercent();

        uint256 _userShareBeforeCommision = (_totalRewards * usersETH) / TOTAL_STAKED_ETH;

        _protocolShare = (protocolFeePercent * _userShareBeforeCommision) / 100;

        _operatorShare = (_totalRewards * collateralETH) / TOTAL_STAKED_ETH;
        _operatorShare += (operatorFeePercent * _userShareBeforeCommision) / 100;

        _userShare = _totalRewards - _protocolShare - _operatorShare;
    }

    function settleFunds() external nonReentrant onlyRole(STADER_NODE_REGISTRY_CONTRACT) {
        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = _calculateValidatorWithdrawShare();

        // Final settlement
        IStaderStakePoolManager(staderConfig.stakePoolManager()).receiveWithdrawVaultUserShare{value: userShare}();
        _sendValue(nodeRecipient, operatorShare);
        _sendValue(payable(staderConfig.treasury()), protocolShare);
    }

    // TODO: add penalty changes
    function _calculateValidatorWithdrawShare()
        internal
        view
        returns (
            uint256 _userShare,
            uint256 _operatorShare,
            uint256 _protocolShare
        )
    {
        uint256 TOTAL_STAKED_ETH = staderConfig.totalStakedEth();
        uint256 collateralETH = getCollateralETH(); // 0, incase of permissioned NOs
        uint256 usersETH = TOTAL_STAKED_ETH - collateralETH;
        uint256 contractBalance = address(this).balance;

        uint256 totalRewards;

        if (contractBalance < usersETH) {
            _userShare = contractBalance;
            return (_userShare, _operatorShare, _protocolShare);
        } else if (contractBalance < TOTAL_STAKED_ETH) {
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

    function _sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, 'Address: insufficient balance');

        //slither-disable-next-line arbitrary-send-eth
        if (amount > 0) {
            (bool success, ) = recipient.call{value: amount}(''); // TODO: Manoj check if call is best ??
            require(success, 'Address: unable to send value, recipient may have reverted');
        }
    }

    // getters

    function getProtocolFeePercent() internal view returns (uint256) {
        return IPoolFactory(staderConfig.poolFactory()).getProtocolFeePercent(poolId);
    }

    // should return 0, for permissioned NOs
    function getOperatorFeePercent() internal view returns (uint256) {
        return IPoolFactory(staderConfig.poolFactory()).getOperatorFeePercent(poolId);
    }

    function getCollateralETH() private view returns (uint256) {
        return IPoolFactory(staderConfig.poolFactory()).getCollateralETH(poolId);
    }
}
