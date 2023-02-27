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
        uint256 protocolShare = calculateProtocolShare();
        uint256 operatorShare = calculateOperatorShare();
        uint256 userShare = calculateUserShare();

        bool success;

        // Distribute rewards
        IStaderStakePoolManager(staderStakePoolsManager).receiveExecutionLayerRewards{value: userShare}();
        (success, ) = payable(staderTreasury).call{value: protocolShare}('');
        require(success, 'Protocol share transfer failed');
        (success, ) = payable(nodeRecipient).call{value: operatorShare}('');
        require(success, 'Operator share transfer failed');

        emit Withdrawal(protocolShare, operatorShare, userShare);
    }

    function calculateProtocolShare() public view override returns (uint256) {
        return address(this).balance * (getProtocolFeePercent() / 100);
    }

    function calculateOperatorShare() public view override returns (uint256) {
        uint256 fullBalance = address(this).balance;
        uint256 remainingBalance = fullBalance - calculateProtocolShare();
        uint256 halfBalance = remainingBalance / 2;
        uint256 operatorFee = halfBalance * (getOperatorFeePercent() / 100);
        return halfBalance + operatorFee;
    }

    function calculateUserShare() public view override returns (uint256) {
        uint256 fullBalance = address(this).balance;
        uint256 remainingBalance = fullBalance - calculateProtocolShare();
        return remainingBalance - calculateOperatorShare();
    }

    function getProtocolFeePercent() internal view returns (uint256) {
        return IPoolFactory(poolFactory).getProtocolFeePercent(poolId);
    }

    function getOperatorFeePercent() internal view returns (uint256) {
        return IPoolFactory(poolFactory).getOperatorFeePercent(poolId);
    }
}
