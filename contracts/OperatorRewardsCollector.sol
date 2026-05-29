// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { UtilLib } from "./library/UtilLib.sol";

import { IStaderConfig } from "./interfaces/IStaderConfig.sol";
import { INodeRegistry } from "./interfaces/INodeRegistry.sol";
import { INodeELRewardVault } from "./interfaces/INodeELRewardVault.sol";
import { IPermissionlessNodeRegistry } from "./interfaces/IPermissionlessNodeRegistry.sol";
import { IOperatorRewardsCollector } from "./interfaces/IOperatorRewardsCollector.sol";
import { IStaderConfig } from "./interfaces/IStaderConfig.sol";
import { ISDUtilityPool, UserData, OperatorLiquidation } from "./interfaces/ISDUtilityPool.sol";
import { ISDCollateral } from "./interfaces/SDCollateral/ISDCollateral.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { IStaderOracle } from "../contracts/interfaces/IStaderOracle.sol";
import { IPoolUtils } from "../contracts/interfaces/IPoolUtils.sol";

contract OperatorRewardsCollector is IOperatorRewardsCollector, AccessControlUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IStaderConfig public staderConfig;

    mapping(address => uint256) public balances;

    IWETH public weth;

    bool public assetCustodied;
    uint256 public sweepToCustodyTimestamp;

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
        if (assetCustodied) revert AssetCustodied();
        uint256 amount;
        if (_isPermissionlessCaller(msg.sender)) {
            claimLiquidation(msg.sender);
            amount = balances[msg.sender] > withdrawableInEth(msg.sender)
                ? withdrawableInEth(msg.sender)
                : balances[msg.sender];
        } else {
            amount = balances[msg.sender];
        }
        _claim(msg.sender, amount);
    }

    /**
     * @notice function to claim a given amount of ETH, this is done to make sure operator can claim
     * any desired amount such that their health factor remains above 1
     * @dev amount should not be more than the minimum of operator balance and withdrawableInEth after completing liquidation if any
     * @param _amount amount of ETH to claim
     */
    function claimWithAmount(uint256 _amount) external {
        if (assetCustodied) revert AssetCustodied();
        if (_isPermissionlessCaller(msg.sender)) {
            claimLiquidation(msg.sender);
            uint256 maxWithdrawableInEth = withdrawableInEth(msg.sender);
            if (_amount > maxWithdrawableInEth) revert InsufficientBalance();
        }
        if (_amount > balances[msg.sender]) revert InsufficientBalance();
        _claim(msg.sender, _amount);
    }

    function claimLiquidation(address operator) public override {
        if (assetCustodied) revert AssetCustodied();
        _transferBackUtilizedSD(operator);
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
        uint256 sdPriceInETH = IStaderOracle(staderConfig.getStaderOracle()).getSDPriceInETH();

        uint256 totalInterestAdjustedInEth = Math.ceilDiv(
            (totalInterestAdjusted * sdPriceInETH),
            staderConfig.getDecimals()
        );

        if (totalInterestAdjustedInEth > userData.totalCollateralInEth) return 0;
        uint256 withdrawableAmountInEth = userData.totalCollateralInEth - totalInterestAdjustedInEth;

        OperatorLiquidation memory operatorLiquidation = sdUtilityPool.getOperatorLiquidation(operator);
        return
            withdrawableAmountInEth > operatorLiquidation.totalAmountInEth
                ? withdrawableAmountInEth - operatorLiquidation.totalAmountInEth
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

    function _isPermissionlessCaller(address caller) internal returns (bool) {
        IPoolUtils poolUtils = IPoolUtils(staderConfig.getPoolUtils());
        uint8 poolId = poolUtils.getOperatorPoolId(caller);
        address permissionlessNodeRegistry = staderConfig.getPermissionlessNodeRegistry();

        return INodeRegistry(permissionlessNodeRegistry).POOL_ID() == poolId;
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
            (uint8 poolId, uint256 operatorId, uint256 nonTerminalKeys) = ISDCollateral(staderConfig.getSDCollateral())
                .getOperatorInfo(operator);
            // Ensure that the balance is sufficient
            if (balances[operator] < operatorLiquidation.totalAmountInEth && nonTerminalKeys > 0) {
                revert InsufficientBalance();
            }
            address permissionlessNodeRegistry = staderConfig.getPermissionlessNodeRegistry();
            if (INodeRegistry(permissionlessNodeRegistry).POOL_ID() == poolId) {
                address nodeELVault = IPermissionlessNodeRegistry(permissionlessNodeRegistry)
                    .nodeELRewardVaultByOperatorId(operatorId);
                if (nodeELVault.balance > 0) {
                    INodeELRewardVault(nodeELVault).withdraw();
                }
            }
            if (balances[operator] < operatorLiquidation.totalAmountInEth) {
                uint256 wETHDeposit = Math.min(
                    balances[operator],
                    operatorLiquidation.totalAmountInEth - operatorLiquidation.totalFeeInEth
                );

                weth.deposit{ value: wETHDeposit }();
                if (weth.transferFrom(address(this), operatorLiquidation.liquidator, wETHDeposit) == false)
                    revert WethTransferFailed();
                balances[operator] -= wETHDeposit;

                uint256 protocolFee = Math.min(operatorLiquidation.totalFeeInEth, balances[operator]);
                UtilLib.sendValue(staderConfig.getStaderTreasury(), protocolFee);

                balances[operator] -= protocolFee;
                sdUtilityPool.completeLiquidation(operator);
            } else {
                // Transfer WETH to liquidator and ETH to treasury
                weth.deposit{ value: operatorLiquidation.totalAmountInEth - operatorLiquidation.totalFeeInEth }();
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
    }

    /**
     * @notice Internal function to claim a specified amount for an operator.
     * @dev Deducts the amount from the operator's balance and transfers it to their rewards address.
     *      It also checks if the claiming amount does not exceed the withdrawable limit or the operator's balance.
     * @param operator The address of the operator claiming the amount.
     * @param amount The amount to be claimed.
     */
    function _claim(address operator, uint256 amount) internal {
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

        uint256 operatorUtilizedSDBal = sdCollateral.operatorUtilizedSDBalance(operator);

        // Only proceed if the operator has no non-terminal (active) keys left and nonZero utilizedSD Balance
        if (nonTerminalKeys > 0 || (operatorUtilizedSDBal == 0)) return;

        // transfer back the operator's utilized SD balance to SD Utility Pool
        sdCollateral.transferBackUtilizedSD(operator);
    }

    /// @notice admin-driven settle: pay liquidator, treasury covers SD interest (when keys terminal), push remaining ETH to operator
    /// @dev Manager-only. Used during sunset wind-down for delinquent/unreachable operators.
    /// @param op operator to settle
    function adminSettleOperator(address op) external {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);

        claimLiquidation(op);

        (, , uint256 nonTerminalKeys) = ISDCollateral(staderConfig.getSDCollateral()).getOperatorInfo(op);
        UserData memory ud = ISDUtilityPool(staderConfig.getSDUtilityPool()).getUserData(op);
        if (nonTerminalKeys == 0 && ud.totalInterestSD > 0) {
            IERC20Upgradeable sd = IERC20Upgradeable(staderConfig.getStaderToken());
            address treasury = staderConfig.getStaderTreasury();
            address sdUtilityPool = staderConfig.getSDUtilityPool();
            sd.safeTransferFrom(treasury, address(this), ud.totalInterestSD);
            sd.safeApprove(sdUtilityPool, 0);
            sd.safeApprove(sdUtilityPool, ud.totalInterestSD);
            ISDUtilityPool(sdUtilityPool).repayOnBehalf(op, ud.totalInterestSD);
            uint256 sdPriceInEth = IStaderOracle(staderConfig.getStaderOracle()).getSDPriceInETH();
            uint256 interestInEth = (ud.totalInterestSD * sdPriceInEth) / staderConfig.getDecimals();
            uint256 ethToTreasury = Math.min(balances[op], interestInEth);
            if (ethToTreasury > 0) {
                balances[op] -= ethToTreasury;
                UtilLib.sendValue(treasury, ethToTreasury);
            }
        }
        if (balances[op] > 0) _claim(op, balances[op]);
        emit AdminSettledOperator(op);
    }

    /// @notice arm custody sweep timer; sweepToCustody allowed only after delay elapses
    /// @dev Admin (timelock) only
    function setCustodyDelay(uint256 _custodyDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_custodyDelay == 0) revert ZeroCustodyDelay();
        sweepToCustodyTimestamp = block.timestamp + _custodyDelay;
        emit SetCustodyDelay(sweepToCustodyTimestamp);
    }

    /// @notice sweep full ETH or ERC20 balance to custody; sticky-flips assetCustodied
    /// @dev Admin (timelock) only; requires armed setCustodyDelay() with elapsed delay
    function sweepToCustody(address _asset, address _custody) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_custody == address(0)) revert ZeroAddress();
        if (sweepToCustodyTimestamp == 0 || block.timestamp < sweepToCustodyTimestamp) revert CustodyDelayNotElapsed();
        assetCustodied = true;
        uint256 bal;
        if (_asset == address(0)) {
            bal = address(this).balance;
            if (bal == 0) revert ZeroAmount();
            (bool success, ) = payable(_custody).call{ value: bal }("");
            if (!success) revert TransferFailed();
        } else {
            bal = IERC20Upgradeable(_asset).balanceOf(address(this));
            if (bal == 0) revert ZeroAmount();
            IERC20Upgradeable(_asset).safeTransfer(_custody, bal);
        }
        emit SweptToCustody(_asset, _custody, bal);
    }
}
