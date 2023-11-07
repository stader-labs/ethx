// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

import './interfaces/IStaderConfig.sol';
import './library/UtilLib.sol';

/**
 * @title SDx token Contract
 * @author Stader Labs
 * @notice The ERC20 contract for the SDx token
 */

contract SDX is Initializable, ERC20Upgradeable, PausableUpgradeable, AccessControlUpgradeable {
    event UpdatedStaderConfig(address indexed _staderConfig);

    IStaderConfig public staderConfig;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _staderConfig) external initializer {
        UtilLib.checkNonZeroAddress(_admin);
        UtilLib.checkNonZeroAddress(_staderConfig);

        __ERC20_init('Interest bearing SD token', 'SDx');
        __Pausable_init();
        __AccessControl_init();

        staderConfig = IStaderConfig(_staderConfig);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        emit UpdatedStaderConfig(_staderConfig);
    }

    /**
     * @notice Mints SDx when called by an authorized caller
     * @param to the account to mint to
     * @param amount the amount of SDx to mint
     */
    function mint(address to, uint256 amount) external whenNotPaused {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.SD_UTILITY_POOL());

        _mint(to, amount);
    }

    /**
     * @notice Burns SDx when called by an authorized caller
     * @param account the account to burn from
     * @param amount the amount of SDx to burn
     */
    function burnFrom(address account, uint256 amount) external whenNotPaused {
        UtilLib.onlyStaderContract(msg.sender, staderConfig, staderConfig.SD_UTILITY_POOL());

        _burn(account, amount);
    }

    /**
     * @dev Triggers stopped state.
     * Contract must not be paused.
     */
    function pause() external {
        UtilLib.onlyManagerRole(msg.sender, staderConfig);

        _pause();
    }

    /**
     * @dev Returns to normal state.
     * Contract must be paused
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function updateStaderConfig(address _staderConfig) external onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }
}