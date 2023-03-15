// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/INodeELRewardVault.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPoolFactory.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

contract NodeELRewardVault is INodeELRewardVault, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    // Pool information
    uint8 public poolId;
    address public poolFactory;

    // Recipients
    address payable public nodeRecipient;
    address payable public staderTreasury;
    address payable public staderStakePoolsManager;

    uint256 public constant TOTAL_STAKED_ETH = 32 ether;

    function initialize(
        address _owner,
        address payable _nodeRecipient,
        address payable _staderTreasury,
        address payable _staderStakePoolsManager,
        address _poolFactory,
        uint8 _poolId
    ) external initializer {
        Address.checkNonZeroAddress(_owner);
        Address.checkNonZeroAddress(_nodeRecipient);
        Address.checkNonZeroAddress(_staderTreasury);
        Address.checkNonZeroAddress(_staderStakePoolsManager);
        Address.checkNonZeroAddress(_poolFactory);

        staderTreasury = _staderTreasury;
        nodeRecipient = _nodeRecipient;
        staderStakePoolsManager = _staderStakePoolsManager;
        poolFactory = _poolFactory;
        poolId = _poolId;

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);

        __AccessControl_init();
        __ReentrancyGuard_init();
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
        IStaderStakePoolManager(staderStakePoolsManager).receiveExecutionLayerRewards{value: userShare}();
        // slither-disable-next-line arbitrary-send-eth
        (success, ) = payable(staderTreasury).call{value: protocolShare}('');
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

    function getProtocolFeePercent() internal view returns (uint256) {
        return IPoolFactory(poolFactory).getProtocolFeePercent(poolId);
    }

    function getOperatorFeePercent() internal view returns (uint256) {
        return IPoolFactory(poolFactory).getOperatorFeePercent(poolId);
    }

    function getCollateralETH() private view returns (uint256) {
        return IPoolFactory(poolFactory).getCollateralETH(poolId);
    }
}
