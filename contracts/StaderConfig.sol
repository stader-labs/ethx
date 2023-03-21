// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './interfaces/IStaderConfig.sol';

contract StaderConfig is IStaderConfig, Initializable, AccessControlUpgradeable {
    uint256 public totalStakedEth;
    uint256 public rewardThreshold;

    // ACCOUNTS
    address public admin;
    address public treasury;
    address public stakePoolManager;

    // TOKENS
    address public staderToken;
    address public wethToken;

    // CONTRACTS
    address public poolFactory;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin) external initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        admin = _admin;
    }

    // SETTERS

    // TODO: Manoj propose-accept two step required ??
    function updateAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(DEFAULT_ADMIN_ROLE, admin);
        admin = _admin;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    function updateTotalStakedEth(uint256 _totalStakedEth) external onlyRole(DEFAULT_ADMIN_ROLE) {
        totalStakedEth = _totalStakedEth;
    }

    function updateRewardThreshold(uint256 _rewardThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        rewardThreshold = _rewardThreshold;
    }

    function updateStaderToken(address _staderToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        staderToken = _staderToken;
    }

    function updateWethToken(address _wethToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        wethToken = _wethToken;
    }

    function updateTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        treasury = _treasury;
    }

    function updatePoolFactory(address _poolFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        poolFactory = _poolFactory;
    }

    function updateStakePoolManager(address _stakePoolManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        stakePoolManager = _stakePoolManager;
    }
}
