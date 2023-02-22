// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/IStaderNodeWithdrawManager.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderNodeWithdrawManager is IStaderNodeWithdrawManager, Initializable, AccessControlUpgradeable {
    bytes32 public constant override STADER_POOL_MANAGER = keccak256('STADER_POOL_MANAGER');

    bytes32 public constant override WITHDRAW_VAULT = keccak256('WITHDRAW_VAULT');

    nodeWithdrawInfo[] public override nodeWithdrawRequest;

    mapping(bytes => uint256) public override requestIdByPubKey;

    /// @notice withdrawal requests mapped to the operatorId
    mapping(uint256 => uint256[]) internal requestsByOperatorId;

    struct nodeWithdrawInfo {
        bool claimed;
        bool requestProcessed;
        address payable recipient;
        bytes pubKey;
        uint256 operatorId;
        uint256 amount;
        uint256 requestBlockNumber;
    }

    function initialize() external initializer {
        __AccessControl_init_unchained();
    }

    function requestNodeWithdraw(
        address payable _recipient,
        bytes memory _pubKey,
        uint256 _operatorId
    ) external override onlyRole(STADER_POOL_MANAGER) returns (uint256 requestId) {
        requestId = nodeWithdrawRequest.length;
        nodeWithdrawRequest.push(nodeWithdrawInfo(false, false, _recipient, _pubKey, _operatorId, 0, block.number));
        requestIdByPubKey[_pubKey] = requestId;
        requestsByOperatorId[_operatorId].push(requestId);
        return requestId;
    }

    function processNodeWithdraw(bytes memory _pubKey) external payable override onlyRole(WITHDRAW_VAULT) {
        uint256 requestId = requestIdByPubKey[_pubKey];
        nodeWithdrawRequest[requestId].requestProcessed = true;
        nodeWithdrawRequest[requestId].amount = msg.value;
    }

    function nodeRedeem(uint256 requestId) external override onlyRole(STADER_POOL_MANAGER) {
        if (!nodeWithdrawRequest[requestId].requestProcessed) revert NodeWithdrawRequestNotProcessed(requestId);
        if (nodeWithdrawRequest[requestId].claimed) revert NodeWithdrawRequestAlreadyClaim(requestId);
        nodeWithdrawRequest[requestId].claimed = true;
        _sendValue(nodeWithdrawRequest[requestId].recipient, nodeWithdrawRequest[requestId].amount);
    }

    function nodeBatchRedeem(uint256 _operatorId) external override onlyRole(STADER_POOL_MANAGER) {
        uint256[] memory requestsIds = requestsByOperatorId[_operatorId];
        for (uint256 i = 0; i < requestsIds.length; i++) {
            if (nodeWithdrawRequest[requestsIds[i]].requestProcessed) {
                nodeWithdrawRequest[requestsIds[i]].claimed = true;
                _sendValue(nodeWithdrawRequest[requestsIds[i]].recipient, nodeWithdrawRequest[requestsIds[i]].amount);
            }
        }
    }

    /// @notice Returns all withdrawal requests placed for the `_recipient` address
    function getNodeWithdrawalRequests(uint256 _operatorId) external view returns (uint256[] memory requestsIds) {
        return requestsByOperatorId[_operatorId];
    }

    function _sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, 'Address: insufficient balance');

        // solhint-disable-next-line
        (bool success, ) = recipient.call{value: amount}('');
        require(success, 'Address: unable to send value, recipient may have reverted');
    }
}
