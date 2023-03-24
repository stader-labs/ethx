// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

import './interfaces/IStaderConfig.sol';

import './library/Address.sol';

contract StaderConfig is IStaderConfig, Initializable, AccessControlUpgradeable {
    enum Constant {
        FullDepositSizeOnBeaconChain, // full deposit value on beacon chain i.e. 32 ETH
        DECIMALS, // ETH to WEI ratio i.e 10**18
        OPERATOR_MAX_NAME_LENGTH //maximum length of operator name string
    }

    enum Variable {
        RewardsThreshold,
        MinDepositAmount,
        MaxDepositAmount,
        MinWithdrawAmount,
        MaxWithdrawAmount
    }

    enum Account {
        MultiSigAdmin,
        StaderTreasury,
        StaderPenaltyFund
    }

    enum Contract {
        TWAPGetter,
        PoolFactory,
        PoolSelector,
        PriceFetcher,
        SDCollateral,
        VaultFactory,
        StaderOracle,
        PenaltyContract,
        PermissionedPool,
        StakePoolManager,
        ETHDepositContract,
        PermissionlessPool,
        UserWithdrawManager,
        PermissionedNodeRegistry,
        PermissionlessNodeRegistry,
        PermissionedSocializePool,
        PermissionlessSocializePool
    }

    enum Token {
        SD,
        WETH,
        ETHx
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

    //TODO sanjay implement Timelock controller
    function initialize(address _admin, address _ethDepositContract) external initializer {
        Address.checkNonZeroAddress(_admin);
        Address.checkNonZeroAddress(_ethDepositContract);
        __AccessControl_init();
        _setConstant(Constant.FullDepositSizeOnBeaconChain, 32 ether);
        _setConstant(Constant.DECIMALS, 10**18);
        _setConstant(Constant.OPERATOR_MAX_NAME_LENGTH, 255);
        _setVariable(Variable.MinDepositAmount, 100);
        _setVariable(Variable.MaxDepositAmount, 10000 ether);
        _setVariable(Variable.MinWithdrawAmount, 100);
        _setVariable(Variable.MaxWithdrawAmount, 10000 ether);
        _setContract(Contract.ETHDepositContract, _ethDepositContract);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setAccount(Account.MultiSigAdmin, _admin);
    }

    //Variables Setters

    function updateRewardsThreshold(uint256 _rewardsThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVariable(Variable.RewardsThreshold, _rewardsThreshold);
    }

    /**
     * @dev update the minimum stake amount
     * @param _minDepositAmount minimum deposit value
     */
    function updateMinDepositAmount(uint256 _minDepositAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_minDepositAmount == 0 || _minDepositAmount > getMaxDepositAmount()) revert InvalidMinDepositValue();
        _setVariable(Variable.MinDepositAmount, _minDepositAmount);
    }

    /**
     * @dev update the maximum stake amount
     * @param _maxDepositAmount maximum deposit value
     */
    function updateMaxDepositAmount(uint256 _maxDepositAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_maxDepositAmount <= getMinDepositAmount()) revert InvalidMaxDepositValue();
        _setVariable(Variable.MaxDepositAmount, _maxDepositAmount);
    }

    /**
     * @dev update the minimum withdraw amount
     * @param _minWithdrawAmount minimum withdraw value
     */
    function updateMinWithdrawAmount(uint256 _minWithdrawAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_minWithdrawAmount == 0 || _minWithdrawAmount > getMaxWithdrawAmount()) revert InvalidMinWithdrawValue();
        _setVariable(Variable.MinWithdrawAmount, _minWithdrawAmount);
    }

    /**
     * @dev update the maximum withdraw amount
     * @param _maxWithdrawAmount maximum withdraw value
     */
    function updateMaxWithdrawAmount(uint256 _maxWithdrawAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_maxWithdrawAmount < getMinWithdrawAmount()) revert InvalidMaxWithdrawValue();
        _setVariable(Variable.MaxWithdrawAmount, _maxWithdrawAmount);
    }

    //Accounts Setters

    // TODO: Manoj propose-accept two step required ??
    function updateAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldAdmin = getMultiSigAdmin();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setAccount(Account.MultiSigAdmin, _admin);

        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
    }

    function updateStaderTreasury(address _staderTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setAccount(Account.StaderTreasury, _staderTreasury);
    }

    function updateStaderPenaltyFund(address _staderPenaltyFund) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setAccount(Account.StaderPenaltyFund, _staderPenaltyFund);
    }

    // Contracts Setters

    function updateTWAPGetter(address _twapGetter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.TWAPGetter, _twapGetter);
    }

    function updatePoolFactory(address _poolFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.PoolFactory, _poolFactory);
    }

    function updatePoolSelector(address _poolSelector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.PoolSelector, _poolSelector);
    }

    function updatePriceFetcher(address _priceFetcher) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.PriceFetcher, _priceFetcher);
    }

    function updateSDCollateral(address _sdCollateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.SDCollateral, _sdCollateral);
    }

    function updateVaultFactory(address _vaultFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.VaultFactory, _vaultFactory);
    }

    function updateStaderOracle(address _staderOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.StaderOracle, _staderOracle);
    }

    function updatePenaltyContract(address _penaltyContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.PenaltyContract, _penaltyContract);
    }

    function updatePermissionedPool(address _permissionedPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.PermissionedPool, _permissionedPool);
    }

    function updateStakePoolManager(address _stakePoolManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.StakePoolManager, _stakePoolManager);
    }

    function updatePermissionlessPool(address _permissionlessPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.PermissionlessPool, _permissionlessPool);
    }

    function updateUserWithdrawManager(address _userWithdrawManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.UserWithdrawManager, _userWithdrawManager);
    }

    function updatePermissionedNodeRegistry(address _permissionedNodeRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.PermissionedNodeRegistry, _permissionedNodeRegistry);
    }

    function updatePermissionlessNodeRegistry(address _permissionlessNodeRegistry)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setContract(Contract.PermissionlessNodeRegistry, _permissionlessNodeRegistry);
    }

    function updatePermissionedSocializePool(address _permissionedSocializePool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(Contract.PermissionedSocializePool, _permissionedSocializePool);
    }

    function updatePermissionlessSocializePool(address _permissionlessSocializePool)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setContract(Contract.PermissionlessSocializePool, _permissionlessSocializePool);
    }

    function updateStaderToken(address _staderToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setToken(Token.SD, _staderToken);
    }

    function updateWethToken(address _wethToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setToken(Token.WETH, _wethToken);
    }

    function updateETHxToken(address _ethX) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setToken(Token.ETHx, _ethX);
    }

    //Constants Getters

    function getFullDepositOnBeaconChain() external view override returns (uint256) {
        return constantsMap[Constant.FullDepositSizeOnBeaconChain];
    }

    function getDecimals() external view override returns (uint256) {
        return constantsMap[Constant.DECIMALS];
    }

    function getOperatorMaxNameLength() external view override returns (uint256) {
        return constantsMap[Constant.OPERATOR_MAX_NAME_LENGTH];
    }

    //Variables Getters

    function getRewardsThreshold() external view override returns (uint256) {
        return variablesMap[Variable.RewardsThreshold];
    }

    function getMinDepositAmount() public view override returns (uint256) {
        return variablesMap[Variable.MinDepositAmount];
    }

    function getMaxDepositAmount() public view override returns (uint256) {
        return variablesMap[Variable.MaxDepositAmount];
    }

    function getMinWithdrawAmount() public view override returns (uint256) {
        return variablesMap[Variable.MinWithdrawAmount];
    }

    function getMaxWithdrawAmount() public view override returns (uint256) {
        return variablesMap[Variable.MaxWithdrawAmount];
    }

    //Account Getters

    function getMultiSigAdmin() public view returns (address) {
        return accountsMap[Account.MultiSigAdmin];
    }

    function getStaderTreasury() external view override returns (address) {
        return accountsMap[Account.StaderTreasury];
    }

    function getStaderPenaltyFund() external view override returns (address) {
        return accountsMap[Account.StaderPenaltyFund];
    }

    //Contracts Getters

    function getTWAPGetter() external view override returns (address) {
        return contractsMap[Contract.TWAPGetter];
    }

    function getPoolFactory() external view override returns (address) {
        return contractsMap[Contract.PoolFactory];
    }

    function getPoolSelector() external view override returns (address) {
        return contractsMap[Contract.PoolSelector];
    }

    function getPriceFetcher() external view override returns (address) {
        return contractsMap[Contract.PriceFetcher];
    }

    function getSDCollateral() external view override returns (address) {
        return contractsMap[Contract.SDCollateral];
    }

    function getVaultFactory() external view override returns (address) {
        return contractsMap[Contract.VaultFactory];
    }

    function getStaderOracle() external view override returns (address) {
        return contractsMap[Contract.StaderOracle];
    }

    function getPenaltyContract() external view override returns (address) {
        return contractsMap[Contract.PenaltyContract];
    }

    function getPermissionedPool() external view override returns (address) {
        return contractsMap[Contract.PermissionedPool];
    }

    function getStakePoolManager() external view override returns (address) {
        return contractsMap[Contract.StakePoolManager];
    }

    function getETHDepositContract() external view override returns (address) {
        return contractsMap[Contract.ETHDepositContract];
    }

    function getPermissionlessPool() external view override returns (address) {
        return contractsMap[Contract.PermissionlessPool];
    }

    function getUserWithdrawManager() external view override returns (address) {
        return contractsMap[Contract.UserWithdrawManager];
    }

    function getPermissionedNodeRegistry() external view override returns (address) {
        return contractsMap[Contract.PermissionedNodeRegistry];
    }

    function getPermissionlessNodeRegistry() external view override returns (address) {
        return contractsMap[Contract.PermissionlessNodeRegistry];
    }

    function getPermissionedSocializePool() external view override returns (address) {
        return contractsMap[Contract.PermissionedSocializePool];
    }

    function getPermissionlessSocializePool() external view override returns (address) {
        return contractsMap[Contract.PermissionlessSocializePool];
    }

    //Token Getters

    function getStaderToken() external view override returns (address) {
        return tokensMap[Token.SD];
    }

    function getWethToken() external view override returns (address) {
        return tokensMap[Token.WETH];
    }

    function getETHxToken() external view returns (address) {
        return tokensMap[Token.ETHx];
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
}
