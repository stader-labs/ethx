// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './interfaces/IStaderConfig.sol';

import './library/Address.sol';

contract StaderConfig is IStaderConfig, Initializable, AccessControlUpgradeable {
    enum Constant {
        StakedEthPerNode
    }

    enum Variable {
        RewardsThreshold
    }

    enum Account {
        Admin,
        Treasury,
        StakePoolManager
    }

    enum Contract {
        PoolFactory,
        StaderOracle,
        SocializingPool
    }

    enum Token {
        SD,
        WETH
    }

    mapping(Constant => uint256) private constantsMap; // TODO: Manoj discuss losing flexibility on constant/variable type allowed
    mapping(Variable => uint256) private variablesMap;
    mapping(Account => address) private accountsMap;
    mapping(Contract => address) private contractsMap;
    mapping(Token => address) private tokensMap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin) external initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setAccount(Account.Admin, _admin);
    }

    // SETTERS

    function updateStakedEthPerNode(uint256 _stakedEthPerNode) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setConstant(Constant.StakedEthPerNode, _stakedEthPerNode);
    }

    function updateRewardsThreshold(uint256 _rewardsThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVariable(Variable.RewardsThreshold, _rewardsThreshold);
    }

    // TODO: Manoj propose-accept two step required ??
    function updateAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldAdmin = getAdmin();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setAccount(Account.Admin, _admin);

        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
    }

    function updateTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setAccount(Account.Treasury, _treasury);
    }

    function updateStakePoolManager(address _stakePoolManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setAccount(Account.StakePoolManager, _stakePoolManager);
    }

    function updatePoolFactory(address _poolFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.PoolFactory, _poolFactory);
    }

    function updateStaderOracle(address _staderOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.StaderOracle, _staderOracle);
    }

    function updateSocializingPool(address _socializingPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.SocializingPool, _socializingPool);
    }

    function updateStaderToken(address _staderToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setToken(Token.SD, _staderToken);
    }

    function updateWethToken(address _wethToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setToken(Token.WETH, _wethToken);
    }

    // SETTER HELPERS
    function _setConstant(Constant key, uint256 val) internal {
        constantsMap[key] = val;
        emit SetConstant(uint256(key), val);
    }

    function _setVariable(Variable key, uint256 val) internal {
        variablesMap[key] = val;
        emit SetConstant(uint256(key), val);
    }

    function _setAccount(Account key, address val) internal {
        Address.checkNonZeroAddress(val);
        accountsMap[key] = val;
        emit SetAccount(uint256(key), val);
    }

    function _setContract(Contract key, address val) internal {
        Address.checkNonZeroAddress(val);
        contractsMap[key] = val;
        emit SetContract(uint256(key), val);
    }

    function _setToken(Token key, address val) internal {
        Address.checkNonZeroAddress(val);
        tokensMap[key] = val;
        emit SetToken(uint256(key), val);
    }

    // GETTERS

    function getStakedEthPerNode() external view override returns (uint256) {
        return constantsMap[Constant.StakedEthPerNode];
    }

    function getRewardsThreshold() external view override returns (uint256) {
        return variablesMap[Variable.RewardsThreshold];
    }

    function getAdmin() public view returns (address) {
        return accountsMap[Account.Admin];
    }

    function getTreasury() external view override returns (address) {
        return accountsMap[Account.Treasury];
    }

    function getStakePoolManager() external view override returns (address) {
        return accountsMap[Account.StakePoolManager];
    }

    function getPoolFactory() external view override returns (address) {
        return contractsMap[Contract.PoolFactory];
    }

    function getStaderOracle() external view override returns (address) {
        return contractsMap[Contract.StaderOracle];
    }

    function getSocializingPool() external view override returns (address) {
        return contractsMap[Contract.SocializingPool];
    }

    function getStaderToken() external view override returns (address) {
        return tokensMap[Token.SD];
    }

    function getWethToken() external view override returns (address) {
        return tokensMap[Token.WETH];
    }
}
