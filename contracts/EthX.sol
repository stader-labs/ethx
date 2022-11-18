// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

/**
 * @title ethX Contract
 * @author Stader Labs
 * @notice The ERC20 contract for the ethX token
 */
contract ETHX is ERC20, ERC20Burnable, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    constructor() ERC20("ETHX", "ETHX") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /**
     * @notice Mints ethX when called by an authorized caller
     * @param to the account to mint to
     * @param amount the amount of ethX to mint
     */
    function mint(address to, uint256 amount)
        external
        onlyRole(MINTER_ROLE)
        whenNotPaused
    {
        _mint(to, amount);
    }

    /**
     * @notice Burns ethX when called by an authorized caller
     * @param account the account to burn from
     * @param amount the amount of ethX to burn
     */
    function burnFrom(address account, uint256 amount)
        public
        override
        onlyRole(MINTER_ROLE)
        whenNotPaused
    {
        _burn(account, amount);
    }

    function pause() public onlyRole(PAUSER_ROLE) whenNotPaused {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }
}
