// SPDX-License-Identifier: MIT
pragma solidity >=0.7.5;

interface IStaderConfig {
    // events
    event SetConstant(uint256, uint256);
    event SetVariable(uint256, uint256);
    event SetAccount(uint256, address);
    event SetContract(uint256, address);
    event SetToken(uint256, address);

    // Constants
    function getStakedEthPerNode() external view returns (uint256);

    // Variables
    function getRewardsThreshold() external view returns (uint256);

    // Accounts
    function getAdmin() external view returns (address);

    function getTreasury() external view returns (address);

    function getStakePoolManager() external view returns (address);

    // Contracts
    function getPoolFactory() external view returns (address);

    // Tokens
    function getStaderToken() external view returns (address);

    function getWethToken() external view returns (address);
}
