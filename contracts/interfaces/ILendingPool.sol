// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './IStaderConfig.sol';

interface ILendingPool {

    // events
    event UpdatedStaderConfig(address staderConfig);

    // functions
    function deposit(uint256 amount) external returns (uint256);

    function withdraw(uint256 amount) external returns (uint256);

    function claim(uint256 index) external returns (uint256);

}