// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface IPoolDeposit {
    function STADER_POOL_MANAGER() external view returns (bytes32);

    function depositEthToDepositContract(uint256 operatorId) external payable;
}
