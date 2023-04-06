// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/AddressLib.sol';

import './interfaces/IStaderConfig.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderConfig is IStaderConfig, Initializable, AccessControlUpgradeable {
    // staked ETH per node on beacon chain i.e. 32 ETH
    bytes32 public constant ETH_PER_NODE = keccak256('ETH_PER_NODE');
    // ETH to WEI ratio i.e 10**18
    bytes32 public constant DECIMALS = keccak256('DECIMALS');
    //maximum length of operator name string
    bytes32 public constant OPERATOR_MAX_NAME_LENGTH = keccak256('OPERATOR_MAX_NAME_LENGTH');

    bytes32 public constant SOCIALIZING_POOL_CYCLE_DURATION = keccak256('SOCIALIZING_POOL_CYCLE_DURATION');
    bytes32 public constant SOCIALIZING_POOL_OPT_IN_COOLING_PERIOD =
        keccak256('SOCIALIZING_POOL_OPT_IN_COOLING_PERIOD');
    bytes32 public constant REWARD_THRESHOLD = keccak256('REWARD_THRESHOLD');
    bytes32 public constant MIN_DEPOSIT_AMOUNT = keccak256('MIN_DEPOSIT_AMOUNT');
    bytes32 public constant MAX_DEPOSIT_AMOUNT = keccak256('MAX_DEPOSIT_AMOUNT');
    bytes32 public constant MIN_WITHDRAW_AMOUNT = keccak256('MIN_WITHDRAW_AMOUNT');
    bytes32 public constant MAX_WITHDRAW_AMOUNT = keccak256('MAX_WITHDRAW_AMOUNT');
    //minimum delay between user requesting withdraw and request finalization
    bytes32 public constant MIN_DELAY_TO_FINALIZE_WITHDRAW_REQUEST =
        keccak256('MIN_DELAY_TO_FINALIZE_WITHDRAW_REQUEST');

    bytes32 public constant ADMIN = keccak256('ADMIN');
    bytes32 public constant STADER_TREASURY = keccak256('STADER_TREASURY');
    bytes32 public constant STADER_PENALTY_FUND = keccak256('STADER_PENALTY_FUND');

    bytes32 public constant POOL_FACTORY = keccak256('POOL_FACTORY');
    bytes32 public constant POOL_SELECTOR = keccak256('POOL_SELECTOR');
    bytes32 public constant SD_COLLATERAL = keccak256('SD_COLLATERAL');
    bytes32 public constant VAULT_FACTORY = keccak256('VAULT_FACTORY');
    bytes32 public constant STADER_ORACLE = keccak256('STADER_ORACLE');
    bytes32 public constant AUCTION_CONTRACT = keccak256('AuctionContract');
    bytes32 public constant PENALTY_CONTRACT = keccak256('PENALTY_CONTRACT');
    bytes32 public constant PERMISSIONED_POOL = keccak256('PERMISSIONED_POOL');
    bytes32 public constant STAKE_POOL_MANAGER = keccak256('STAKE_POOL_MANAGER');
    bytes32 public constant ETH_DEPOSIT_CONTRACT = keccak256('ETH_DEPOSIT_CONTRACT');
    bytes32 public constant PERMISSIONLESS_POOL = keccak256('PERMISSIONLESS_POOL');
    bytes32 public constant USER_WITHDRAW_MANAGER = keccak256('USER_WITHDRAW_MANAGER');
    bytes32 public constant STADER_INSURANCE_FUND = keccak256('STADER_INSURANCE_FUND');
    bytes32 public constant PERMISSIONED_NODE_REGISTRY = keccak256('PERMISSIONED_NODE_REGISTRY');
    bytes32 public constant PERMISSIONLESS_NODE_REGISTRY = keccak256('PERMISSIONLESS_NODE_REGISTRY');
    bytes32 public constant PERMISSIONED_SOCIALIZING_POOL = keccak256('PERMISSIONED_SOCIALIZING_POOL');
    bytes32 public constant PERMISSIONLESS_SOCIALIZING_POOL = keccak256('PERMISSIONLESS_SOCIALIZING_POOL');

    bytes32 public constant SD = keccak256('SD');
    bytes32 public constant WETH = keccak256('WETH');
    bytes32 public constant ETHx = keccak256('ETHx');

    mapping(bytes32 => uint256) private constantsMap; // TODO: Manoj discuss losing flexibility on constant/variable type allowed
    mapping(bytes32 => uint256) private variablesMap;
    mapping(bytes32 => address) private accountsMap;
    mapping(bytes32 => address) private contractsMap;
    mapping(bytes32 => address) private tokensMap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _ethDepositContract) external initializer {
        AddressLib.checkNonZeroAddress(_admin);
        AddressLib.checkNonZeroAddress(_ethDepositContract);
        __AccessControl_init();
        _setConstant(ETH_PER_NODE, 32 ether);
        _setConstant(DECIMALS, 10**18);
        _setConstant(OPERATOR_MAX_NAME_LENGTH, 255);
        _setVariable(MIN_DEPOSIT_AMOUNT, 100);
        _setVariable(MAX_DEPOSIT_AMOUNT, 10000 ether);
        _setVariable(MIN_WITHDRAW_AMOUNT, 100);
        _setVariable(MAX_WITHDRAW_AMOUNT, 10000 ether);
        _setContract(ETH_DEPOSIT_CONTRACT, _ethDepositContract);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setAccount(ADMIN, _admin);
    }

    //Variables Setters

    function updateSocializingPoolCycleDuration(uint256 _socializingPoolCycleDuration)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setVariable(SOCIALIZING_POOL_CYCLE_DURATION, _socializingPoolCycleDuration);
    }

    function updateSocializingPoolOptInCoolingPeriod(uint256 _SocializePoolOptInCoolingPeriod)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setVariable(SOCIALIZING_POOL_OPT_IN_COOLING_PERIOD, _SocializePoolOptInCoolingPeriod);
    }

    function updateRewardsThreshold(uint256 _rewardsThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVariable(REWARD_THRESHOLD, _rewardsThreshold);
    }

    /**
     * @dev update the minimum deposit amount
     * @param _minDepositAmount minimum deposit amount
     */
    function updateMinDepositAmount(uint256 _minDepositAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_minDepositAmount == 0 || _minDepositAmount > getMaxDepositAmount()) {
            revert InvalidMinDepositValue();
        }
        _setVariable(MIN_DEPOSIT_AMOUNT, _minDepositAmount);
    }

    /**
     * @dev update the maximum deposit amount
     * @param _maxDepositAmount maximum deposit amount
     */
    function updateMaxDepositAmount(uint256 _maxDepositAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_maxDepositAmount < getMinDepositAmount()) {
            revert InvalidMaxDepositValue();
        }
        _setVariable(MAX_DEPOSIT_AMOUNT, _maxDepositAmount);
    }

    /**
     * @dev update the minimum withdraw amount
     * @param _minWithdrawAmount minimum withdraw amount
     */
    //TODO sanjay not clear on one review comment
    function updateMinWithdrawAmount(uint256 _minWithdrawAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_minWithdrawAmount == 0 || _minWithdrawAmount > getMaxWithdrawAmount()) {
            revert InvalidMinWithdrawValue();
        }
        _setVariable(MIN_WITHDRAW_AMOUNT, _minWithdrawAmount);
    }

    /**
     * @dev update the maximum withdraw amount
     * @param _maxWithdrawAmount maximum withdraw amount
     */
    function updateMaxWithdrawAmount(uint256 _maxWithdrawAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_maxWithdrawAmount < getMinWithdrawAmount()) {
            revert InvalidMaxWithdrawValue();
        }
        _setVariable(MAX_WITHDRAW_AMOUNT, _maxWithdrawAmount);
    }

    function updateMinDelayToFinalizeWithdrawRequest(uint256 _minDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVariable(MIN_DELAY_TO_FINALIZE_WITHDRAW_REQUEST, _minDelay);
    }

    //Accounts Setters

    // TODO: Manoj propose-accept two step required ??
    function updateAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldAdmin = getAdmin();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setAccount(ADMIN, _admin);

        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
    }

    function updateStaderTreasury(address _staderTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setAccount(STADER_TREASURY, _staderTreasury);
    }

    function updateStaderPenaltyFund(address _staderPenaltyFund) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setAccount(STADER_PENALTY_FUND, _staderPenaltyFund);
    }

    // Contracts Setters

    function updatePoolFactory(address _poolFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(POOL_FACTORY, _poolFactory);
    }

    function updatePoolSelector(address _poolSelector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(POOL_SELECTOR, _poolSelector);
    }

    function updateSDCollateral(address _sdCollateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(SD_COLLATERAL, _sdCollateral);
    }

    function updateVaultFactory(address _vaultFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(VAULT_FACTORY, _vaultFactory);
    }

    function updateAuctionContract(address _auctionContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(AUCTION_CONTRACT, _auctionContract);
    }

    function updateStaderOracle(address _staderOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(STADER_ORACLE, _staderOracle);
    }

    function updatePenaltyContract(address _penaltyContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(PENALTY_CONTRACT, _penaltyContract);
    }

    function updatePermissionedPool(address _permissionedPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(PERMISSIONED_POOL, _permissionedPool);
    }

    function updateStakePoolManager(address _stakePoolManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(STAKE_POOL_MANAGER, _stakePoolManager);
    }

    function updatePermissionlessPool(address _permissionlessPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(PERMISSIONLESS_POOL, _permissionlessPool);
    }

    function updateUserWithdrawManager(address _userWithdrawManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(USER_WITHDRAW_MANAGER, _userWithdrawManager);
    }

    function updateStaderInsuranceFund(address _staderInsuranceFund) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(STADER_INSURANCE_FUND, _staderInsuranceFund);
    }

    function updatePermissionedNodeRegistry(address _permissionedNodeRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(PERMISSIONED_NODE_REGISTRY, _permissionedNodeRegistry);
    }

    function updatePermissionlessNodeRegistry(address _permissionlessNodeRegistry)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setContract(PERMISSIONLESS_NODE_REGISTRY, _permissionlessNodeRegistry);
    }

    function updatePermissionedSocializingPool(address _permissionedSocializePool)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setContract(PERMISSIONED_SOCIALIZING_POOL, _permissionedSocializePool);
    }

    function updatePermissionlessSocializingPool(address _permissionlessSocializePool)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setContract(PERMISSIONLESS_SOCIALIZING_POOL, _permissionlessSocializePool);
    }

    function updateStaderToken(address _staderToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setToken(SD, _staderToken);
    }

    function updateWethToken(address _wethToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setToken(WETH, _wethToken);
    }

    function updateETHxToken(address _ethX) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setToken(ETHx, _ethX);
    }

    //Constants Getters

    function getStakedEthPerNode() external view override returns (uint256) {
        return constantsMap[ETH_PER_NODE];
    }

    function getDecimals() external view override returns (uint256) {
        return constantsMap[DECIMALS];
    }

    function getOperatorMaxNameLength() external view override returns (uint256) {
        return constantsMap[OPERATOR_MAX_NAME_LENGTH];
    }

    //Variables Getters

    function getSocializingPoolCycleDuration() public view override returns (uint256) {
        return variablesMap[SOCIALIZING_POOL_CYCLE_DURATION];
    }

    function getSocializingPoolOptInCoolingPeriod() external view override returns (uint256) {
        return variablesMap[SOCIALIZING_POOL_OPT_IN_COOLING_PERIOD];
    }

    function getRewardsThreshold() external view override returns (uint256) {
        return variablesMap[REWARD_THRESHOLD];
    }

    function getMinDepositAmount() public view override returns (uint256) {
        return variablesMap[MIN_DEPOSIT_AMOUNT];
    }

    function getMaxDepositAmount() public view override returns (uint256) {
        return variablesMap[MAX_DEPOSIT_AMOUNT];
    }

    function getMinWithdrawAmount() public view override returns (uint256) {
        return variablesMap[MIN_WITHDRAW_AMOUNT];
    }

    function getMaxWithdrawAmount() public view override returns (uint256) {
        return variablesMap[MAX_WITHDRAW_AMOUNT];
    }

    function getMinDelayToFinalizeWithdrawRequest() external view override returns (uint256) {
        return variablesMap[MIN_DELAY_TO_FINALIZE_WITHDRAW_REQUEST];
    }

    //Account Getters

    function getAdmin() public view returns (address) {
        return accountsMap[ADMIN];
    }

    function getStaderTreasury() external view override returns (address) {
        return accountsMap[STADER_TREASURY];
    }

    function getStaderPenaltyFund() external view override returns (address) {
        return accountsMap[STADER_PENALTY_FUND];
    }

    //Contracts Getters

    function getPoolFactory() external view override returns (address) {
        return contractsMap[POOL_FACTORY];
    }

    function getPoolSelector() external view override returns (address) {
        return contractsMap[POOL_SELECTOR];
    }

    function getSDCollateral() external view override returns (address) {
        return contractsMap[SD_COLLATERAL];
    }

    function getVaultFactory() external view override returns (address) {
        return contractsMap[VAULT_FACTORY];
    }

    function getStaderOracle() external view override returns (address) {
        return contractsMap[STADER_ORACLE];
    }

    function getAuctionContract() external view override returns (address) {
        return contractsMap[AUCTION_CONTRACT];
    }

    function getPenaltyContract() external view override returns (address) {
        return contractsMap[PENALTY_CONTRACT];
    }

    function getPermissionedPool() external view override returns (address) {
        return contractsMap[PERMISSIONED_POOL];
    }

    function getStakePoolManager() external view override returns (address) {
        return contractsMap[STAKE_POOL_MANAGER];
    }

    function getETHDepositContract() external view override returns (address) {
        return contractsMap[ETH_DEPOSIT_CONTRACT];
    }

    function getPermissionlessPool() external view override returns (address) {
        return contractsMap[PERMISSIONLESS_POOL];
    }

    function getUserWithdrawManager() external view override returns (address) {
        return contractsMap[USER_WITHDRAW_MANAGER];
    }

    function getStaderInsuranceFund() external view override returns (address) {
        return contractsMap[STADER_INSURANCE_FUND];
    }

    function getPermissionedNodeRegistry() external view override returns (address) {
        return contractsMap[PERMISSIONED_NODE_REGISTRY];
    }

    function getPermissionlessNodeRegistry() external view override returns (address) {
        return contractsMap[PERMISSIONLESS_NODE_REGISTRY];
    }

    function getPermissionedSocializingPool() external view override returns (address) {
        return contractsMap[PERMISSIONED_SOCIALIZING_POOL];
    }

    function getPermissionlessSocializingPool() external view override returns (address) {
        return contractsMap[PERMISSIONLESS_SOCIALIZING_POOL];
    }

    //Token Getters

    function getStaderToken() external view override returns (address) {
        return tokensMap[SD];
    }

    function getWethToken() external view override returns (address) {
        return tokensMap[WETH];
    }

    function getETHxToken() external view returns (address) {
        return tokensMap[ETHx];
    }

    // SETTER HELPERS
    function _setConstant(bytes32 key, uint256 val) internal {
        constantsMap[key] = val;
        emit SetConstant(key, val);
    }

    function _setVariable(bytes32 key, uint256 val) internal {
        variablesMap[key] = val;
        emit SetConstant(key, val);
    }

    function _setAccount(bytes32 key, address val) internal {
        AddressLib.checkNonZeroAddress(val);
        accountsMap[key] = val;
        emit SetAccount(key, val);
    }

    function _setContract(bytes32 key, address val) internal {
        AddressLib.checkNonZeroAddress(val);
        contractsMap[key] = val;
        emit SetContract(key, val);
    }

    function _setToken(bytes32 key, address val) internal {
        AddressLib.checkNonZeroAddress(val);
        tokensMap[key] = val;
        emit SetToken(key, val);
    }
}
