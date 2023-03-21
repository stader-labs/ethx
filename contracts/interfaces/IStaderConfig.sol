// SPDX-License-Identifier: MIT
pragma solidity >=0.7.5;

interface IStaderConfig {
    function admin() external view returns (address);

    function staderToken() external view returns (address);

    function wethToken() external view returns (address);

    function totalStakedEth() external view returns (uint256);

    function rewardThreshold() external view returns (uint256);

    function treasury() external view returns (address);

    function stakePoolManager() external view returns (address);

    function poolFactory() external view returns (address);
}
