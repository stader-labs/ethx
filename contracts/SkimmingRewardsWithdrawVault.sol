// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';

import {Operator} from './interfaces/INodeRegistry.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';
import './interfaces/IStaderNodeWithdrawManager.sol';

contract StaderWithdrawVault is Initializable {
    address payable public staderPoolManager;
    address payable public staderTreasury;

    Operator public operator;
    uint256 public stakedEthSize;
    uint256 public userStakeSize;
    uint256 public validatorStakeSize;

    uint256 public staderCommision;
    uint256 public validatorCommision;

    function initialize(address _operator) external initializer {
        Address.checkNonZeroAddress(_operator);

        stakedEthSize = 32;
        validatorStakeSize = 4;
        userStakeSize = 28;
        // operator = _operator; // TODO: check with sanjay, in which contract the operator is stored.
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev skimmed rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        // emit ETHReceived(msg.value);
    }

    function distributeRewards() public {
        uint256 rewards = address(this).balance - stakedEthSize;
        (uint256 userRewards, uint256 operatorRewards, uint256 daoRewards) = _calculateRewards(rewards);

        IStaderStakePoolManager(staderPoolManager).receiveWithdrawVaultUserShare{value: userRewards}();
        _sendValue(staderTreasury, daoRewards);

        // operatorRewards will be zero in case of permissioned pool NOs
        if (operatorRewards > 0) {
            _sendValue(operator.operatorRewardAddress, operatorRewards);
        }
    }

    function _calculateRewards(
        uint256 _totalRewards
    ) internal view returns (uint256 _userRewards, uint256 _operatorRewards, uint256 _daoRewards) {
        uint256 _userRewardsBeforeCommision = (userStakeSize * _totalRewards) / stakedEthSize;
        _userRewards = ((100 - staderCommision - validatorCommision) * _userRewardsBeforeCommision) / 100;

        _operatorRewards = (validatorStakeSize * _totalRewards) / stakedEthSize;
        _operatorRewards += (100 + validatorCommision) * _userRewardsBeforeCommision;

        _daoRewards = (staderCommision * _userRewardsBeforeCommision) / 100;
    }

    function _sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, 'Address: insufficient balance');

        //slither-disable-next-line arbitrary-send-eth
        (bool success, ) = recipient.call{value: amount}('');
        require(success, 'Address: unable to send value, recipient may have reverted');
    }
}
