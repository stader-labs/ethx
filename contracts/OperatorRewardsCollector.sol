// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './library/UtilLib.sol';

import './interfaces/IOperatorRewardsCollector.sol';
import './interfaces/IStaderConfig.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract OperatorRewardsCollector is IOperatorRewardsCollector, AccessControlUpgradeable {
    IStaderConfig public staderConfig;

    mapping(address => uint256) public balances;

    mapping(address => uint256)[] public owedAmounts;
    mapping(address => uint256)[] public claimableAmounts;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _staderConfig) external initializer {
        UtilLib.checkNonZeroAddress(_admin);
        UtilLib.checkNonZeroAddress(_staderConfig);

        __AccessControl_init();

        staderConfig = IStaderConfig(_staderConfig);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        emit UpdatedStaderConfig(_staderConfig);
    }

    function depositFor(address _receiver) external payable {
        balances[_receiver] += msg.value;

        emit DepositedFor(msg.sender, _receiver, msg.value);
    }

    function claim() external {
        address operator = msg.sender;
        uint256 amount = balances[operator];
        balances[operator] -= amount;

        address operatorRewardsAddr = UtilLib.getOperatorRewardAddress(msg.sender, staderConfig);
        UtilLib.sendValue(operatorRewardsAddr, amount);
        emit Claimed(operatorRewardsAddr, amount);
    }

    function claimFor(address operator) external {
        uint256 toSendAmount;
        for (uint256 i = 0; i < owedAmounts[operator].length; i++) {
            if (balances[operator] >= owedAmounts[operator][i]) {
                toSendAmount = owedAmounts[operator][i];
                balances[operator] -= owedAmounts[operator][i];
                claimableAmounts[operator][i] = owedAmounts[operator][i];
                owedAmounts[operator][i] = 0;
            } else {
                toSendAmount = balances[operator];
                owedAmounts[operator][i] -= balances[operator];
                claimableAmounts[operator][i] = balances[operator];
                balances[operator] = 0;
                break;
            }
        }

        if (balances[operator] > 0) {
            address operatorRewardsAddr = UtilLib.getOperatorRewardAddress(operator, staderConfig);
            UtilLib.sendValue(operatorRewardsAddr, balances[operator]);
            emit Claimed(operatorRewardsAddr, balances[operator]);
        }
    }

    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }
}
