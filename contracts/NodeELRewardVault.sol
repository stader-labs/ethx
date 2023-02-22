// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract NodeELRewardVault is Initializable, AccessControlUpgradeable {
    address payable nodeRecipient;
    address payable staderTreasury;

    event ETHReceived(uint256 amout);

    function initialize(
        address _owner,
        address payable _nodeRecipient,
        address payable _staderTreasury
    ) external initializer {
        Address.checkNonZeroAddress(_owner);
        Address.checkNonZeroAddress(_nodeRecipient);
        Address.checkNonZeroAddress(_staderTreasury);
        __AccessControl_init_unchained();
        staderTreasury = _staderTreasury;
        nodeRecipient = _nodeRecipient;
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev execution layer rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.value);
    }
}
