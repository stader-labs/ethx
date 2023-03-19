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
    address public staderConfig;

    // Pool information
    uint8 public poolId;

    // Recipients
    address payable public nodeRecipient;

    function initialize(
        address _owner,
        address _staderConfig,
        address payable _nodeRecipient,
        uint8 _poolId
    ) external initializer {
        Address.checkNonZeroAddress(_owner);
        Address.checkNonZeroAddress(_staderConfig);
        Address.checkNonZeroAddress(_nodeRecipient);

        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);

        staderConfig = _staderConfig;
        nodeRecipient = _nodeRecipient;
        poolId = _poolId;
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev execution layer rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.value);
    }

    function withdraw() external override nonReentrant {
        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = _calculateRewardShare(
            address(this).balance
        );

        bool success;

        // Distribute rewards
        IStaderStakePoolManager(getStaderStakePoolManager()).receiveExecutionLayerRewards{value: userShare}();
        // slither-disable-next-line arbitrary-send-eth
        (success, ) = payable(getStaderTreasury()).call{value: protocolShare}('');
        require(success, 'Protocol share transfer failed');
        // slither-disable-next-line arbitrary-send-eth
        (success, ) = payable(nodeRecipient).call{value: operatorShare}('');
        require(success, 'Operator share transfer failed');

        emit Withdrawal(protocolShare, operatorShare, userShare);
    }

    function _calculateRewardShare(uint256 _totalRewards)
        internal
        view
        returns (
            uint256 _userShare,
            uint256 _operatorShare,
            uint256 _protocolShare
        )
    {
        uint256 TOTAL_STAKED_ETH = getTotalStakedEth();
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

    function getTotalStakedEth() public view returns (uint256) {
        return IStaderConfig(staderConfig).totalStakedEth();
    }

    function getPoolFactory() public view returns (address) {
        return IStaderConfig(staderConfig).poolFactory();
    }

    function getStaderTreasury() public view returns (address) {
        return IStaderConfig(staderConfig).treasury();
    }

    function getStaderStakePoolManager() public view returns (address) {
        return IStaderConfig(staderConfig).stakePoolManager();
    }

    function getProtocolFeePercent() internal view returns (uint256) {
        return IPoolFactory(getPoolFactory()).getProtocolFeePercent(poolId);
    }

    function getOperatorFeePercent() internal view returns (uint256) {
        return IPoolFactory(getPoolFactory()).getOperatorFeePercent(poolId);
    }

    function getCollateralETH() private view returns (uint256) {
        return IPoolFactory(getPoolFactory()).getCollateralETH(poolId);
    }
}
