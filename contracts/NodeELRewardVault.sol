pragma solidity ^0.8.16;

import './library/StaderBaseLibrary.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract NodeELRewardVault is Initializable, AccessControlUpgradeable {
    address payable nodeRecipient;

    event ETHReceived(uint256 amout);

    function initialize(address payable _nodeRecipient) external initializer {
        StaderBaseLibrary.checkZeroAddress(_nodeRecipient);
        __AccessControl_init_unchained();
        nodeRecipient = _nodeRecipient;
    }
    
    // TODO compute user shares of MEV rewards and transfer to the pool manager
    function transferUserShare() external {}
    
    //TODO compute node share
    function transferNodeShareToNodeWithdrawManager() external{}

    /**
     * @notice Allows the contract to receive ETH
     * @dev execution layer rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.value);
    }
}
