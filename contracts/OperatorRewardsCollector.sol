// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './library/UtilLib.sol';

import './interfaces/IOperatorRewardsCollector.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/ISDUtilityPool.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract OperatorRewardsCollector is IOperatorRewardsCollector, AccessControlUpgradeable {
    IStaderConfig public staderConfig;

    mapping(address => uint256) public balances;

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
        return claimFor(msg.sender);
    }

    function claimFor(address operator) public override {
        // Retrieve operator liquidation details
        ISDUtilityPool sdUtilityPool = ISDUtilityPool(staderConfig.getSDUtilityPool());
        OperatorLiquidaton memory operatorLiquidation = sdUtilityPool.getOperatorLiquidation(operator);

        // If the liquidation is not repaid, check balance and then proceed with repayment
        if (!operatorLiquidation.isRepaid) {
            // Ensure that the balance is sufficient
            require(balances[operator] >= operatorLiquidation.amount, 'Insufficient balance');

            // Repay the liquidation and update the operator's balance
            sdUtilityPool.repayLiquidation(operator);
            balances[operator] -= operatorLiquidation.amount;
        }

        // Calculate payout amount
        uint256 payoutAmount = balances[operator];
        balances[operator] = 0;

        // If there's an amount to send, transfer it to the operator's rewards address
        if (payoutAmount > 0) {
            address rewardsAddress = UtilLib.getOperatorRewardAddress(operator, staderConfig);
            UtilLib.sendValue(rewardsAddress, payoutAmount);
            emit Claimed(rewardsAddress, payoutAmount);
        }
    }

    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }
}
