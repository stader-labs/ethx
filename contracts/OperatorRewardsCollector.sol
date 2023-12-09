// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './library/UtilLib.sol';

import './interfaces/IOperatorRewardsCollector.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/ISDUtilityPool.sol';
import './interfaces/IStaderOracle.sol';

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
        return claimFor(msg.sender, 0);
    }

    /**
     * @notice Claims payouts for an operator, repaying any outstanding liquidations and transferring any remaining balance to the operator's rewards address.
     * @dev This function first checks for any unpaid liquidations for the operator and repays them if necessary. Then, it transfers any remaining balance to the operator's reward address.
     * @param operator The address of the operator for whom the claim is being made.
     */
    function claimFor(address operator, uint256 amount) public override {
        if (amount == 0) amount = balances[operator]; // If no amount is specified, claim the full balance

        // Retrieve operator liquidation details
        ISDUtilityPool sdUtilityPool = ISDUtilityPool(staderConfig.getSDUtilityPool());
        OperatorLiquidation memory operatorLiquidation = sdUtilityPool.getOperatorLiquidation(operator);

        // If the liquidation is not repaid, check balance and then proceed with repayment
        if (!operatorLiquidation.isRepaid && operatorLiquidation.totalAmountInEth > 0) {
            // Ensure that the balance is sufficient
            if (balances[operator] < operatorLiquidation.totalAmountInEth) revert InsufficientBalance();

            // Repay the liquidation and update the operator's balance
            sdUtilityPool.repayLiquidation(operator);
            balances[operator] -= operatorLiquidation.totalAmountInEth;
        }

        uint256 maxWithdrawableInEth = withdrawableInEth(operator);

        if (amount > maxWithdrawableInEth || amount > balances[operator]) revert InsufficientBalance();

        balances[operator] -= amount;

        // If there's an amount to send, transfer it to the operator's rewards address
        if (amount > 0) {
            address rewardsAddress = UtilLib.getOperatorRewardAddress(operator, staderConfig);
            UtilLib.sendValue(rewardsAddress, amount);
            emit Claimed(rewardsAddress, amount);
        }
    }

    /**
     * @notice Distributes the liquidation payout and fee. It sends a specified amount to the liquidator and a fee to the Stader treasury.
     * @dev This function should only be called by the SD Utility Pool contract as part of the liquidation process. It uses UtilLib to safely send ETH.
     * @param liquidatorAmount The amount of ETH to be sent to the liquidator.
     * @param feeAmount The amount of ETH to be sent to the Stader treasury as a fee.
     * @param liquidator The address of the liquidator.
     */
    function claimLiquidation(
        uint256 liquidatorAmount,
        uint256 feeAmount,
        address liquidator
    ) external override {
        // Ensure only the SD Utility Pool contract can call this function
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.SD_UTILITY_POOL());

        UtilLib.sendValue(liquidator, liquidatorAmount);
        UtilLib.sendValue(staderConfig.getStaderTreasury(), feeAmount);
    }

    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    function withdrawableInEth(address operator) public view override returns (uint256) {
        ISDUtilityPool sdUtilityPool = ISDUtilityPool(staderConfig.getSDUtilityPool());
        uint256 liquidationThreshold = sdUtilityPool.getLiquidationThreshold();
        UserData memory userData = sdUtilityPool.getUserData(operator);
        uint256 withdrawableInSd = userData.totalCollateralInSD - (userData.totalInterestSD / liquidationThreshold);

        return withdrawableInSd * IStaderOracle(staderConfig.getStaderOracle()).getSDPriceInETH();
    }
}
