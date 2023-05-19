// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/UtilLib.sol';

import './interfaces/IPayments.sol';
import './interfaces/IStaderConfig.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract Payments is IPayments, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    IStaderConfig public staderConfig;

    mapping(address => uint256) public ethBalances;

    function initialize(address _admin, address _staderConfig) external initializer {
        UtilLib.checkNonZeroAddress(_admin);
        UtilLib.checkNonZeroAddress(_staderConfig);

        __AccessControl_init();
        __Pausable_init();

        staderConfig = IStaderConfig(_staderConfig);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        emit UpdatedStaderConfig(_staderConfig);
    }

    function depositFor(address _receiver) external payable {
        ethBalances[_receiver] += msg.value;

        emit EthDepositedFor(msg.sender, _receiver, msg.value);
    }

    function claim() external whenNotPaused {
        _claim(msg.sender);
    }

    function claimByOperator() external whenNotPaused {
        address operatorRewardsAddr = UtilLib.getNodeRecipientAddressByOperator(msg.sender, staderConfig);
        _claim(operatorRewardsAddr);
    }

    function _claim(address _receiver) internal {
        uint256 amount = ethBalances[_receiver];
        ethBalances[_receiver] -= amount;

        sendValue(_receiver, amount);
        emit EthClaimed(_receiver, amount);
    }

    function sendValue(address _receiver, uint256 _amount) internal {
        if (address(this).balance < _amount) {
            revert InSufficientBalance();
        }

        //slither-disable-next-line arbitrary-send-eth
        (bool success, ) = payable(_receiver).call{value: _amount}('');
        if (!success) {
            revert TransferFailed();
        }
    }
}
