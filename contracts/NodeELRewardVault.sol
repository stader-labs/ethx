pragma solidity ^0.8.16;

import './library/Address.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract NodeELRewardVault is Initializable, AccessControlUpgradeable {
    
    address payable nodeRecipient;
    address payable staderTreasury;

    event ETHReceived(uint256 amout);

    function initialize(address payable _nodeRecipient, address payable _staderTreasury) external initializer {
        Address.checkZeroAddress(_nodeRecipient);
        Address.checkZeroAddress(_staderTreasury);
        __AccessControl_init_unchained();
        staderTreasury = _staderTreasury;
        nodeRecipient = _nodeRecipient;
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev execution layer rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.value);
    }
}
