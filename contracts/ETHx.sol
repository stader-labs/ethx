// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/UtilLib.sol';

import './interfaces/IStaderConfig.sol';

import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

/**
 * @title ETHx token Contract
 * @author Stader Labs
 * @notice The ERC20 contract for the ETHx token
 */

contract ETHx is Initializable, ERC20Upgradeable, PausableUpgradeable, AccessControlUpgradeable {
    IStaderConfig staderConfig;
    bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _staderConfig) public initializer {
        UtilLib.checkNonZeroAddress(_staderConfig);

        __ERC20_init('Liquid Staking ETH', 'ETHx');
        __Pausable_init();
        __AccessControl_init();

        staderConfig = IStaderConfig(_staderConfig);
        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    /**
     * @notice Mints ethX when called by an authorized caller
     * @param to the account to mint to
     * @param amount the amount of ethX to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        _mint(to, amount);
    }

    /**
     * @notice Burns ethX when called by an authorized caller
     * @param account the account to burn from
     * @param amount the amount of ethX to burn
     */
    function burnFrom(address account, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        _burn(account, amount);
    }

    /// @notice Flips the pause state
    function togglePause() external onlyRole(PAUSER_ROLE) {
        paused() ? _unpause() : _pause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
}
