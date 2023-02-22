// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IStaderNodeWithdrawManager {
    error NodeWithdrawRequestNotProcessed(uint256 _requestId);

    error NodeWithdrawRequestAlreadyClaim(uint256 _requestId);

    function STADER_POOL_MANAGER() external view returns (bytes32);

    function WITHDRAW_VAULT() external view returns (bytes32);

    function requestNodeWithdraw(
        address payable _recipient,
        bytes memory _pubKey,
        uint256 _operatorId
    ) external returns (uint256 requestId);

    function requestIdByPubKey(bytes memory) external view returns (uint256);

    function processNodeWithdraw(bytes memory _pubKey) external payable;

    function nodeRedeem(uint256 requestId) external;

    function nodeBatchRedeem(uint256 _operatorId) external;

    function nodeWithdrawRequest(uint256)
        external
        view
        returns (
            bool claimed,
            bool requestProcessed,
            address payable recipient,
            bytes memory pubKey,
            uint256 operatorId,
            uint256 amount,
            uint256 requestBlockNumber
        );
}
