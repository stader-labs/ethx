// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

interface ISDUtilityPool {
    error SDTransferFailed();

    function delegate(uint256 sdAmount) external;

    function redeem(uint256 sdXAmount) external;

    function utilize(uint256 utilizeAmount) external;

    function repay(uint256 repayAmount) external;

    function accrueInterest() external;

    function borrowBalanceCurrent(address account) external returns (uint256);

    function borrowBalanceStored(address account) external view returns (uint256);

    function utilizationRate() external view returns (uint256);

    function getSupplyRate() external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function getPoolSDBalance() external view returns (uint256);
}
