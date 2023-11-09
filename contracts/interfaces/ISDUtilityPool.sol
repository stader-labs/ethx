// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

struct UserData {
    uint256 totalFeeSD;
    uint256 totalCollateralInSD;
    uint256 ltv;
    uint256 healthFactor;
    uint256 lockedEth;
}

struct Config {
    uint256 liquidationThreshold;
    uint256 liquidationBonus;
    uint256 ltv;
}

interface ISDUtilityPool {
    error SDTransferFailed();

    function delegate(uint256 sdAmount) external;

    function redeem(uint256 sdXAmount) external;

    function utilize(uint256 utilizeAmount) external;

    function repay(uint256 repayAmount) external;

    function repayOnBehalf(address utilizer, uint256 repayAmount) external;

    function accrueFee() external;

    function liquidationCall(address account) external;

    function utilizeBalanceCurrent(address account) external returns (uint256);

    function utilizeBalanceStored(address account) external view returns (uint256);

    function poolUtilization() external view returns (uint256);

    function getDelegationRate() external view returns (uint256);

    function exchangeRateCurrent() external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function getPoolSDBalance() external view returns (uint256);
}
