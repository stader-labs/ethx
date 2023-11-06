// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './library/UtilLib.sol';
import './SDx.sol';
import './interfaces/IStaderConfig.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract SDUtilityPool is AccessControlUpgradeable, PausableUpgradeable {
    uint256 constant DECIMAL = 1e18;

    /**
     * @notice Fraction of interest currently set aside for protocol fee
     */
    uint256 public feeFactor;

    /**
     * @notice Block number that interest was last accrued at
     */
    uint256 public accrualBlockNumber;

    /**
     * @notice Accumulator of the total earned interest rate since start of pool
     */
    uint256 public borrowIndex;

    /**
     * @notice Total amount of outstanding SD borrows
     */
    uint256 public totalBorrows;

    /**
     * @notice Total amount of protocol fee
     */
    uint256 public totalFee;

    uint256 public borrowRate;

    IStaderConfig public staderConfig;

    //TODO sanjay read below two params from config
    address public sdX;

    address public sdToken;

    struct BorrowerStruct {
        uint256 principal;
        uint256 interestIndex;
    }

    mapping(address => BorrowerStruct) public accountBorrows;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _staderConfig) external initializer {
        UtilLib.checkNonZeroAddress(_admin);
        UtilLib.checkNonZeroAddress(_staderConfig);
        __AccessControl_init_unchained();
        __Pausable_init();
        staderConfig = IStaderConfig(_staderConfig);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Sender supplies SD and receive SDx in return
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param sdAmount The amount of SD token to supply
     */
    function deposit(uint256 sdAmount) external {
        accrueInterest();
        _deposit(sdAmount);
    }

    /**
     * @notice Sender redeems SDx in exchange for the SD token
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param sdXAmount The number of SDx to redeem
     */
    function redeem(uint256 sdXAmount) external {
        accrueInterest();
        _redeem(sdXAmount);
    }

    /**
     * @notice Sender borrows SD from the protocol to add it as collateral to run validators
     * @param borrowAmount The amount of the SD token to borrow
     */
    function borrow(uint256 borrowAmount) external {
        //TODO @sanjay put check to allow only ETHx NOs to borrow and max 1ETH worth of SD per validator
        accrueInterest();
        _borrow(payable(msg.sender), borrowAmount);
    }

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay
     */
    function repay(uint256 repayAmount) external {
        accrueInterest();
        _repay(msg.sender, repayAmount);
    }

    /**
     * @notice Applies accrued interest to total borrows and fees
     * @dev This calculates interest accrued from the last checkpointed block
     *   up to the current block and writes new checkpoint to storage.
     */
    function accrueInterest() public {
        /* Remember the initial block number */
        uint256 currentBlockNumber = block.number;
        uint256 accrualBlockNumberPrior = accrualBlockNumber;

        /* Short-circuit accumulating 0 interest */
        if (accrualBlockNumberPrior == currentBlockNumber) {
            return;
        }

        /* Read the previous values out of storage */
        uint256 borrowsPrior = totalBorrows;
        uint256 reservesPrior = totalFee;
        uint256 borrowIndexPrior = borrowIndex;

        /* Calculate the number of blocks elapsed since the last accrual */
        uint256 blockDelta = currentBlockNumber - accrualBlockNumberPrior;

        /*
         * Calculate the interest accumulated into borrows and reserves and the new index:
         *  simpleInterestFactor = borrowRate * blockDelta
         *  interestAccumulated = simpleInterestFactor * totalBorrows
         *  totalBorrowsNew = interestAccumulated + totalBorrows
         *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
         *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex
         */

        uint256 simpleInterestFactor = borrowRate * blockDelta;
        uint256 interestAccumulated = (simpleInterestFactor * borrowsPrior) / DECIMAL;
        uint256 totalBorrowsNew = interestAccumulated + borrowsPrior;
        uint256 totalReservesNew = (feeFactor * interestAccumulated) / DECIMAL + reservesPrior;
        uint256 borrowIndexNew = (simpleInterestFactor * borrowIndexPrior) / DECIMAL + borrowIndexPrior;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        accrualBlockNumber = currentBlockNumber;
        borrowIndex = borrowIndexNew;
        totalBorrows = totalBorrowsNew;
        totalFee = totalReservesNew;

        //TODO sanjay emit events
    }

    /**
     * @notice Accrue interest to updated borrowIndex and then calculate account's borrow balance using the updated borrowIndex
     * @param account The address whose balance should be calculated after updating borrowIndex
     * @return The calculated balance
     */
    function borrowBalanceCurrent(address account) external returns (uint256) {
        accrueInterest();
        return _borrowBalanceStoredInternal(account);
    }

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return The calculated balance
     */
    function borrowBalanceStored(address account) external view returns (uint256) {
        return _borrowBalanceStoredInternal(account);
    }

    /// @notice Calculates the utilization rate of the utility pool
    function utilizationRate() public view returns (uint256) {
        // Utilization rate is 0 when there are no borrows
        if (totalBorrows == 0) {
            return 0;
        }

        return (totalBorrows * DECIMAL) / (getPoolSDBalance() + totalBorrows - totalFee);
    }

    /// @notice Calculates the current supply rate per block
    function getSupplyRate() public view returns (uint256) {
        uint256 oneMinusReserveFactor = DECIMAL - feeFactor;
        uint256 rateToPool = (borrowRate * oneMinusReserveFactor) / DECIMAL;
        return (utilizationRate() * rateToPool) / DECIMAL;
    }

    /**
     * @notice Accrue interest then return the up-to-date exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() external returns (uint256) {
        accrueInterest();
        return _exchangeRateStoredInternal();
    }

    /**
     * @notice Calculates the exchange rate from the SD to the SDx
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateStored() external view returns (uint256) {
        return _exchangeRateStoredInternal();
    }

    /**
     * @dev Assumes interest has already been accrued up to the current block
     * @param sdAmount The amount of the SD token to supply
     */
    function _deposit(uint256 sdAmount) internal {
        /* Verify `accrualBlockNumber` block number equals current block number */
        if (accrualBlockNumber != block.number) {
            //TODO @sanjay revert
        }

        uint256 exchangeRate = _exchangeRateStoredInternal();

        if (!IERC20(staderConfig.getStaderToken()).transferFrom(msg.sender, address(this), sdAmount)) {
            // revert SDTransferFailed();
        }
        uint256 mintTokens = (sdAmount * DECIMAL) / exchangeRate;
        SDx(sdX).mint(msg.sender, mintTokens);

        //TODO @sanjay emit events
    }

    /**
     * @dev Assumes interest has already been accrued up to the current block
     * @param sdXAmount The amount of the SDx token to to withdraw
     */
    function _redeem(uint256 sdXAmount) internal {
        uint256 exchangeRate = _exchangeRateStoredInternal();
        uint256 redeemAmount = (exchangeRate * sdXAmount) / DECIMAL;

        /* Verify `accrualBlockNumber` block number equals current block number */
        if (accrualBlockNumber != block.number) {
            // revert RedeemFreshnessCheck();
        }

        /* Fail gracefully if protocol has insufficient cash */
        if (getPoolSDBalance() < redeemAmount) {
            //TODO @sanjay revert
        }
        SDx(sdX).burnFrom(msg.sender, sdXAmount);
        if (!IERC20(staderConfig.getStaderToken()).transferFrom(address(this), msg.sender, redeemAmount)) {
            // revert SDTransferFailed();
        }
        //TODO @sanjay emit events
    }

    function _borrow(address payable borrower, uint256 borrowAmount) internal {
        /* Verify `accrualBlockNumber` block number equals current block number */
        if (accrualBlockNumber != block.number) {
            //TODO @sanjay revert
        }

        /* Fail gracefully if protocol has insufficient SD balance in pool */
        if (getPoolSDBalance() < borrowAmount) {
            //TODO @sanjay revert
        }

        uint256 accountBorrowsPrev = _borrowBalanceStoredInternal(borrower);
        uint256 accountBorrowsNew = accountBorrowsPrev + borrowAmount;
        uint256 totalBorrowsNew = totalBorrows + borrowAmount;

        accountBorrows[borrower].principal = accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrowsNew;
        //TODO sanjay bond this borrow amount as SD collateral in SDCollateral contract

        //TODO @sanjay emit events
    }

    function _repay(address borrower, uint256 repayAmount) internal {
        /* Verify `accrualBlockNumber` block number equals current block number */
        if (accrualBlockNumber != block.number) {
            //TODO @sanjay revert
        }

        /* We fetch the amount the borrower owes, with accumulated interest */
        uint256 accountBorrowsPrev = _borrowBalanceStoredInternal(borrower);

        /* If repayAmount == -1, repayAmount = accountBorrows */
        uint256 repayAmountFinal = repayAmount == type(uint256).max ? accountBorrowsPrev : repayAmount;

        //TODO @sanjay
        //transfer interest to this pool and reduce bonded SD position in SDCollateral contract
        uint256 accountBorrowsNew = accountBorrowsPrev - repayAmountFinal;
        uint256 totalBorrowsNew = totalBorrows - repayAmountFinal;

        /* We write the previously calculated values into storage */
        accountBorrows[borrower].principal = accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrowsNew;

        //TODO @sanjay emit events
    }

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return (calculated balance)
     */
    function _borrowBalanceStoredInternal(address account) internal view returns (uint256) {
        /* Get borrowBalance and borrowIndex */
        BorrowerStruct storage borrowSnapshot = accountBorrows[account];

        /* If borrowBalance = 0 then borrowIndex is likely also 0.
         * Rather than failing the calculation with a division by 0, we immediately return 0 in this case.
         */
        if (borrowSnapshot.principal == 0) {
            return 0;
        }

        /* Calculate new borrow balance using the interest index:
         *  recentBorrowBalance = borrower.borrowBalance * market.borrowIndex / borrower.borrowIndex
         */
        uint256 principalTimesIndex = borrowSnapshot.principal * borrowIndex;
        return principalTimesIndex / borrowSnapshot.interestIndex;
    }

    /**
     * @notice Calculates the exchange rate from the SD to the SDx token
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return calculated exchange rate scaled by 1e18
     */
    function _exchangeRateStoredInternal() internal view virtual returns (uint256) {
        uint256 _totalSupply = SDx(sdX).totalSupply();
        if (_totalSupply == 0) {
            /*
             * If there are no tokens minted:
             *  exchangeRate = initialExchangeRate
             */
            return DECIMAL;
        } else {
            /*
             * Otherwise:
             *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
             */
            uint256 poolBalancePlusBorrowsMinusReserves = getPoolSDBalance() + totalBorrows - totalFee;
            uint256 exchangeRate = (poolBalancePlusBorrowsMinusReserves * DECIMAL) / _totalSupply;

            return exchangeRate;
        }
    }

    function getPoolSDBalance() public view returns (uint256) {
        return SDx(sdX).balanceOf(address(this));
    }
}
