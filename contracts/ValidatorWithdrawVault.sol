// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPoolFactory.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';

contract ValidatorWithdrawVault is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    uint8 public poolId;
    address public poolFactory;

    event ETHReceived(uint256 _amount);
    event Withdrawal(uint256 _protocolShare, uint256 _operatorShare, uint256 _userShare);

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

    function withdraw() external nonReentrant {
        uint256 protocolShare = calculateProtocolShare();
        uint256 operatorShare = calculateOperatorShare();
        uint256 userShare = calculateUserShare();

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

    function calculateProtocolShare() public view returns (uint256) {
        return address(this).balance * (getProtocolFeePercent() / 100);
    }

    function calculateOperatorShare() public view returns (uint256) {
        uint256 collateralETH = getCollateralETH();
        uint256 fullBalance = address(this).balance;
        uint256 remainingBalance = fullBalance - calculateProtocolShare();
        uint256 userBalance = (remainingBalance * (32 ether - collateralETH)) / 32 ether;
        uint256 operatorFee = userBalance * (getOperatorFeePercent() / 100);
        return remainingBalance - userBalance + operatorFee;
    }

    function calculateUserShare() public view returns (uint256) {
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

    function getCollateralETH() private view returns (uint256) {
        return IPoolFactory(poolFactory).getCollateralETH(poolId);
    }
}

// /**
//  * @notice Allows the contract to receive ETH
//  * @dev skimmed rewards may be sent as plain ETH transfers
//  */
// receive() external payable {
//     // emit ETHReceived(msg.value);
// }

// function transferUserShareToPoolManager(
//     uint256 _userDeposit,
//     bool _withdrawStatus,
//     address payable _operatorRewardAddress
// ) external onlyRole(POOL_MANAGER) {
//     uint256 userShare = calculateUserShare(_userDeposit, _withdrawStatus);
//     uint256 staderFeeShare = calculateStaderFee(_userDeposit, _withdrawStatus);
//     uint256 nodeShare = calculateNodeShare(validatorDeposit - _userDeposit, _userDeposit, _withdrawStatus);
//     //slither-disable-next-line arbitrary-send-eth
//     IStaderStakePoolManager(staderPoolManager).receiveWithdrawVaultUserShare{value: userShare}();
//     _sendValue(staderTreasury, staderFeeShare);
//     _sendValue(_operatorRewardAddress, nodeShare);
//     //TODO transfer node commission
// }

// function calculateUserShare(uint256 _userDeposit, bool _withdrawStatus) public view returns (uint256) {
//     if (_withdrawStatus) {
//         if (address(this).balance > validatorDeposit) {
//             return
//                 _userDeposit +
//                 ((address(this).balance - validatorDeposit) * _userDeposit * (100 - protocolCommission)) /
//                 (validatorDeposit * 100);
//         } else if (address(this).balance < _userDeposit) {
//             return address(this).balance;
//         } else {
//             return _userDeposit;
//         }
//     }
//     return (address(this).balance * _userDeposit * (100 - protocolCommission)) / (validatorDeposit * 100);
// }

// function calculateNodeShare(
//     uint256 _nodeDeposit,
//     uint256 _userDeposit,
//     bool _withdrawStatus
// ) public view returns (uint256) {
//     require(_nodeDeposit + _userDeposit == validatorDeposit, 'invalid input');
//     if (_withdrawStatus) {
//         if (address(this).balance > validatorDeposit) {
//             return
//                 address(this).balance -
//                 calculateUserShare(_userDeposit, _withdrawStatus) -
//                 calculateStaderFee(_userDeposit, _withdrawStatus);
//         } else if (address(this).balance <= _userDeposit) {
//             return 0;
//         } else {
//             return address(this).balance - _userDeposit;
//         }
//     }
//     return
//         (address(this).balance * _nodeDeposit) /
//         validatorDeposit +
//         ((address(this).balance * _userDeposit * protocolCommission) / (validatorDeposit * 100 * 2));
// }

// function calculateStaderFee(uint256 _userDeposit, bool _withdrawStatus) public view returns (uint256) {
//     if (_withdrawStatus) {
//         if (address(this).balance > validatorDeposit) {
//             return
//                 ((address(this).balance - validatorDeposit) * _userDeposit * protocolCommission) /
//                 (validatorDeposit * 100 * 2);
//         } else {
//             return 0;
//         }
//     }
//     return (address(this).balance * _userDeposit * protocolCommission) / (validatorDeposit * 100 * 2);
// }
