// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/UtilLib.sol';

import './interfaces/ITokenDropBox.sol';
import './interfaces/IStaderConfig.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract TokenDropBox is ITokenDropBox, Initializable, AccessControlUpgradeable, PausableUpgradeable {
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

    function depositEthFor(address _receiver) external payable {
        ethBalances[_receiver] += msg.value;

        emit EthDepositedFor(msg.sender, _receiver, msg.value);
    }

    function claimEth() external whenNotPaused {
        address operator = msg.sender;
        uint256 amount = ethBalances[operator];
        ethBalances[operator] -= amount;

        address operatorRewardsAddr = UtilLib.getOperatorRewardAddress(msg.sender, staderConfig);
        UtilLib.sendValue(operatorRewardsAddr, amount);
        emit EthClaimed(operatorRewardsAddr, amount);
    }
}
