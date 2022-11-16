// File: contracts/StaderManagedStakePool.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2.0;

import "./interfaces/IDepositContract.sol";
import "./interfaces/IStaderValidatorRegistry.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract StaderManagedStakePool is Initializable, OwnableUpgradeable {
    /// event emits after receiving ETH from stader stake pool manager
    event ReceivedFromPoolManager(address indexed from, uint256 amount);

    /**
     * @dev Stader managed stake Pool is initialized with following variables
     */
    function initialize() external initializer {
        __Ownable_init_unchained();
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev stader pool manager send ETH to stader managed stake pool
     */
    function receiveEthFromPoolManager() external payable {
        emit ReceivedFromPoolManager(msg.sender, msg.value);
    }
}
