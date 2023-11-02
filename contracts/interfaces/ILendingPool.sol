// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './IStaderConfig.sol';

struct UserData {
    uint256 totalInterestSD;
    uint256 totalCollateralInSD;
    uint256 ltv;
    uint256 healthFactor;
}

interface ILendingPool {

    // events
    event UpdatedStaderConfig(address staderConfig);

    // functions
    function deposit(uint256 amount) external returns (uint256);

    function requestWithdraw(uint256 amount) external returns (uint256);

    function claim(uint256 index) external returns (uint256);

    function borrow(uint256 amount) external returns (uint256);

    function repay(uint256 amount) external returns (uint256);

    function liquidationCall(address account) external returns (uint256);

    function claimLiquidation(uint256 index) external returns (uint256);

    function getUserData(address account) external view returns (UserData memory);
}