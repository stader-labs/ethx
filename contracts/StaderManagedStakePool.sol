// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./interfaces/IDepositContract.sol";
import "./interfaces/IStaderValidatorRegistry.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

contract StaderManagedStakePool is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    /// event emits after receiving ETH from stader stake pool manager
    event ReceivedETH(address indexed from, uint256 amount);

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
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }
}
