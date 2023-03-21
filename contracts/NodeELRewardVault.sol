// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/INodeELRewardVault.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPoolFactory.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

contract NodeELRewardVault is INodeELRewardVault, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    IStaderConfig public staderConfig;

    // Pool information
    uint8 public poolId;

    // Recipients
    address payable public nodeRecipient;

    function initialize(
        address _staderConfig,
        address payable _nodeRecipient,
        uint8 _poolId
    ) external initializer {
        Address.checkNonZeroAddress(_staderConfig);
        Address.checkNonZeroAddress(_nodeRecipient);

        __AccessControl_init();
        __ReentrancyGuard_init();

        staderConfig = IStaderConfig(_staderConfig);
        nodeRecipient = _nodeRecipient;
        poolId = _poolId;

        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.admin());
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev execution layer rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function withdraw() external override nonReentrant {
        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = _calculateRewardShare(
            address(this).balance
        );

        bool success;

        // Distribute rewards
        IStaderStakePoolManager(staderConfig.stakePoolManager()).receiveExecutionLayerRewards{value: userShare}();
        // slither-disable-next-line arbitrary-send-eth
        (success, ) = payable(staderConfig.treasury()).call{value: protocolShare}('');
        require(success, 'Protocol share transfer failed');
        // slither-disable-next-line arbitrary-send-eth
        (success, ) = payable(nodeRecipient).call{value: operatorShare}('');
        require(success, 'Operator share transfer failed');

        emit Withdrawal(protocolShare, operatorShare, userShare);
    }

    // TODO: add penalty changes
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
        uint256 protocolFeeBps = getProtocolFeeBps();
        uint256 operatorFeeBps = getOperatorFeeBps();

        uint256 _userShareBeforeCommision = (_totalRewards * usersETH) / TOTAL_STAKED_ETH;

        _protocolShare = (protocolFeeBps * _userShareBeforeCommision) / 10000;

        _operatorShare = (_totalRewards * collateralETH) / TOTAL_STAKED_ETH;
        _operatorShare += (operatorFeeBps * _userShareBeforeCommision) / 10000;

        _userShare = _totalRewards - _protocolShare - _operatorShare;
    }

    function getProtocolFeeBps() internal view returns (uint256) {
        return IPoolFactory(staderConfig.poolFactory()).getProtocolFee(poolId);
    }

    function getOperatorFeeBps() internal view returns (uint256) {
        return IPoolFactory(staderConfig.poolFactory()).getOperatorFee(poolId);
    }

    function getCollateralETH() private view returns (uint256) {
        return IPoolFactory(staderConfig.poolFactory()).getCollateralETH(poolId);
    }
}
