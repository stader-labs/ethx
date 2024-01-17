// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './library/UtilLib.sol';

import './interfaces/IOperatorRewardsCollector.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/ISDUtilityPool.sol';
import './interfaces/SDCollateral/ISDCollateral.sol';
import './interfaces/IWETH.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract OperatorRewardsCollector is IOperatorRewardsCollector, AccessControlUpgradeable {
    IStaderConfig public staderConfig;

    mapping(address => uint256) public balances;

    IWETH public weth;

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

    /**
     * @notice Claims payouts for an operator, repaying any outstanding liquidations and transferring any remaining balance to the operator's rewards address.
     * @dev This function first checks for any unpaid liquidations for the operator and repays them if necessary. Then, it transfers any remaining balance to the operator's reward address.
     */
    function claim() external {
        claimLiquidation(msg.sender);
        _transferBackUtilizedSD(msg.sender);

        uint256 amount = balances[msg.sender] > withdrawableInEth(msg.sender)
            ? withdrawableInEth(msg.sender)
            : balances[msg.sender];
        _claim(msg.sender, amount);
    }

    function claimLiquidation(address operator) public override {
        _completeLiquidationIfExists(operator);
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
        uint256 totalInterestAdjusted = (userData.totalInterestSD * 100) / liquidationThreshold;
        uint256 totalInterestAdjustedInEth = ISDCollateral(staderConfig.getSDCollateral()).convertSDToETH(
            totalInterestAdjusted
        );

        if (totalInterestAdjustedInEth > userData.totalCollateralInEth) return 0;
        uint256 withdrawableInEth = userData.totalCollateralInEth - totalInterestAdjustedInEth;

        OperatorLiquidation memory operatorLiquidation = sdUtilityPool.getOperatorLiquidation(operator);
        return
            withdrawableInEth > operatorLiquidation.totalAmountInEth
                ? withdrawableInEth - operatorLiquidation.totalAmountInEth
                : 0;
    }

    function updateWethAddress(address _weth) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_weth);
        weth = IWETH(_weth);
        emit UpdatedWethAddress(_weth);
    }

    function getBalance(address operator) external view override returns (uint256) {
        return balances[operator];
    }

    /**
     * @notice Completes any pending liquidation for an operator if exists.
     * @dev Internal function to handle liquidation completion.
     * @param operator The operator whose liquidation needs to be checked.
     */
    function _completeLiquidationIfExists(address operator) internal {
        // Retrieve operator liquidation details
        ISDUtilityPool sdUtilityPool = ISDUtilityPool(staderConfig.getSDUtilityPool());
        OperatorLiquidation memory operatorLiquidation = sdUtilityPool.getOperatorLiquidation(operator);

        // If the liquidation is not repaid, check balance and then proceed with repayment
        if (!operatorLiquidation.isRepaid && operatorLiquidation.totalAmountInEth > 0) {
            // Ensure that the balance is sufficient
            if (balances[operator] < operatorLiquidation.totalAmountInEth) revert InsufficientBalance();

            // Transfer WETH to liquidator and ETH to treasury
            weth.deposit{value: operatorLiquidation.totalAmountInEth - operatorLiquidation.totalFeeInEth}();
            if (
                weth.transferFrom(
                    address(this),
                    operatorLiquidation.liquidator,
                    operatorLiquidation.totalAmountInEth - operatorLiquidation.totalFeeInEth
                ) == false
            ) revert WethTransferFailed();
            UtilLib.sendValue(staderConfig.getStaderTreasury(), operatorLiquidation.totalFeeInEth);

            sdUtilityPool.completeLiquidation(operator);
            balances[operator] -= operatorLiquidation.totalAmountInEth;
        }
    }

    /**
     * @notice Internal function to claim a specified amount for an operator.
     * @dev Deducts the amount from the operator's balance and transfers it to their rewards address.
     *      It also checks if the claiming amount does not exceed the withdrawable limit or the operator's balance.
     * @param operator The address of the operator claiming the amount.
     * @param amount The amount to be claimed.
     */
    function _claim(address operator, uint256 amount) internal {
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
     * When the operator has no remaining active keys, transfer back the utilized SD to the operator.
     * @param operator The address of the operator whose utilized SD needs to be transferred back.
     */
    function _transferBackUtilizedSD(address operator) internal {
        ISDCollateral sdCollateral = ISDCollateral(staderConfig.getSDCollateral());
        (, , uint256 nonTerminalKeys) = sdCollateral.getOperatorInfo(operator);

        // Only proceed if the operator has no non-terminal (active) keys left
        if (nonTerminalKeys > 0) return;

        // Withdraw the operator's utilized SD balance and transfer it back to SD Utility Pool
        sdCollateral.withdrawOnBehalf(sdCollateral.operatorUtilizedSDBalance(operator), operator);
    }
}
