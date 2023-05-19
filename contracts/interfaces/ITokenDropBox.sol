// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface ITokenDropBox {
    // errors
    error TransferFailed();

    // events
    event UpdatedStaderConfig(address indexed staderConfig);
    event EthClaimed(address indexed receiver, uint256 amount);
    event EthDepositedFor(address indexed sender, address indexed receiver, uint256 amount);

    // methods

    function depositEthFor(address _receiver) external payable;

    function claimEth() external;
}
