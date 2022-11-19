// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2 ;

interface IExecutionLayerRewardContract{

    event ETHReceived(uint256 amount);
    /**
    * @notice Withdraw all accumulated execution layer rewards to Lido contract
    * @return amount of funds received as execution layer rewards (in wei)
    */
    function withdrawELRewards() external returns (uint256 amount);
}


