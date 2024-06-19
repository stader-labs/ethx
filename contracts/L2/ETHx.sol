// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.16;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

/**
 * @title ETHx token Contract for L2s
 * @author Stader Labs
 * @notice The ERC20 contract for the ETHx token
 */
contract ETHx is Initializable, ERC20Upgradeable, PausableUpgradeable, AccessControlUpgradeable {
    error ZeroAddress();

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin) external initializer onlyNonZeroAddress(_admin) {
        __ERC20_init("ETHx", "ETHx");
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
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
    function burnFrom(address account, uint256 amount) external onlyRole(BURNER_ROLE) whenNotPaused {
        _burn(account, amount);
    }

    /**
     * @dev Triggers stopped state.
     * Contract must not be paused.
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * Contract must be paused
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    modifier onlyNonZeroAddress(address _addr) {
        if (_addr == address(0)) {
            revert ZeroAddress();
        }
        _;
    }
}
