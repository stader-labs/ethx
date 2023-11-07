// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import './IStaderConfig.sol';

interface ISDIncentiveController {
    // events
    event UpdatedStaderConfig(address staderConfig);

    // functions
    function claim(address account) external;

    function onDelegate(address account) external;

    function rewardPerToken() external view returns (uint256);

    function earned(address account) external view returns (uint256);
}
