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

    bytes32 public constant SocializingPoolCycleDuration = keccak256('SocializingPoolCycleDuration'); // set it to 28 * 7200
    bytes32 public constant RewardsThreshold = keccak256('RewardsThreshold');
    bytes32 public constant MinDepositAmount = keccak256('MinDepositAmount');
    bytes32 public constant MaxDepositAmount = keccak256('MaxDepositAmount');
    bytes32 public constant MinWithdrawAmount = keccak256('MinWithdrawAmount');
    bytes32 public constant MaxWithdrawAmount = keccak256('MaxWithdrawAmount');
    //minimum delay between user requesting withdraw and request finalization
    bytes32 public constant MIN_DELAY_TO_FINALIZE_WITHDRAW_REQUEST =
        keccak256('MIN_DELAY_TO_FINALIZE_WITHDRAW_REQUEST');

    bytes32 public constant Admin = keccak256('Admin');
    bytes32 public constant StaderTreasury = keccak256('StaderTreasury');
    bytes32 public constant StaderPenaltyFund = keccak256('StaderPenaltyFund');

    bytes32 public constant TWAPGetter = keccak256('TWAPGetter');
    bytes32 public constant PoolFactory = keccak256('PoolFactory');
    bytes32 public constant PoolSelector = keccak256('PoolSelector');
    bytes32 public constant PriceFetcher = keccak256('PriceFetcher');
    bytes32 public constant SDCollateral = keccak256('SDCollateral');
    bytes32 public constant VaultFactory = keccak256('VaultFactory');
    bytes32 public constant StaderOracle = keccak256('StaderOracle');
    bytes32 public constant AuctionContract = keccak256('AuctionContract');
    bytes32 public constant PenaltyContract = keccak256('PenaltyContract');
    bytes32 public constant PermissionedPool = keccak256('PermissionedPool');
    bytes32 public constant StakePoolManager = keccak256('StakePoolManager');
    bytes32 public constant ETHDepositContract = keccak256('ETHDepositContract');
    bytes32 public constant PermissionlessPool = keccak256('PermissionlessPool');
    bytes32 public constant UserWithdrawManager = keccak256('UserWithdrawManager');
    bytes32 public constant PermissionedNodeRegistry = keccak256('PermissionedNodeRegistry');
    bytes32 public constant PermissionlessNodeRegistry = keccak256('PermissionlessNodeRegistry');
    bytes32 public constant PermissionedSocializingPool = keccak256('PermissionedSocializingPool');
    bytes32 public constant PermissionlessSocializingPool = keccak256('PermissionlessSocializingPool');

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
        _setVariable(MinDepositAmount, 100);
        _setVariable(MaxDepositAmount, 10000 ether);
        _setVariable(MinWithdrawAmount, 100);
        _setVariable(MaxWithdrawAmount, 10000 ether);
        _setContract(ETHDepositContract, _ethDepositContract);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setAccount(Admin, _admin);
    }

    //Variables Setters

    function updateSocializingPoolCycleDuration(uint256 _socializingPoolCycleDuration)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setVariable(SocializingPoolCycleDuration, _socializingPoolCycleDuration);
    }

    function updateRewardsThreshold(uint256 _rewardsThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVariable(RewardsThreshold, _rewardsThreshold);
    }

    /**
     * @dev update the minimum deposit amount
     * @param _minDepositAmount minimum deposit amount
     */
    function updateMinDepositAmount(uint256 _minDepositAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_minDepositAmount == 0 || _minDepositAmount > getMaxDepositAmount()) {
            revert InvalidMinDepositValue();
        }
        _setVariable(MinDepositAmount, _minDepositAmount);
    }

    /**
     * @dev update the maximum deposit amount
     * @param _maxDepositAmount maximum deposit amount
     */
    function updateMaxDepositAmount(uint256 _maxDepositAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_maxDepositAmount < getMinDepositAmount()) {
            revert InvalidMaxDepositValue();
        }
        _setVariable(MaxDepositAmount, _maxDepositAmount);
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
        _setVariable(MinWithdrawAmount, _minWithdrawAmount);
    }

    /**
     * @dev update the maximum withdraw amount
     * @param _maxWithdrawAmount maximum withdraw amount
     */
    function updateMaxWithdrawAmount(uint256 _maxWithdrawAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_maxWithdrawAmount < getMinWithdrawAmount()) {
            revert InvalidMaxWithdrawValue();
        }
        _setVariable(MaxWithdrawAmount, _maxWithdrawAmount);
    }

    function updateMinDelayToFinalizeWithdrawRequest(uint256 _minDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setVariable(MIN_DELAY_TO_FINALIZE_WITHDRAW_REQUEST, _minDelay);
    }

    //Accounts Setters

    // TODO: Manoj propose-accept two step required ??
    function updateAdmin(address _admin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldAdmin = getAdmin();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _setAccount(Admin, _admin);

        _revokeRole(DEFAULT_ADMIN_ROLE, oldAdmin);
    }

    function updateStaderTreasury(address _staderTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setAccount(StaderTreasury, _staderTreasury);
    }

    function updateStaderPenaltyFund(address _staderPenaltyFund) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setAccount(StaderPenaltyFund, _staderPenaltyFund);
    }

    // Contracts Setters

    function updateTWAPGetter(address _twapGetter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(TWAPGetter, _twapGetter);
    }

    function updatePoolFactory(address _poolFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(PoolFactory, _poolFactory);
    }

    function updatePoolSelector(address _poolSelector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(PoolSelector, _poolSelector);
    }

    function updatePriceFetcher(address _priceFetcher) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(PriceFetcher, _priceFetcher);
    }

    function updateSDCollateral(address _sdCollateral) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(SDCollateral, _sdCollateral);
    }

    function updateVaultFactory(address _vaultFactory) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(VaultFactory, _vaultFactory);
    }

    function updateAuctionContract(address _auctionContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(AuctionContract, _auctionContract);
    }

    function updateStaderOracle(address _staderOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(StaderOracle, _staderOracle);
    }

    function updatePenaltyContract(address _penaltyContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(PenaltyContract, _penaltyContract);
    }

    function updatePermissionedPool(address _permissionedPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(PermissionedPool, _permissionedPool);
    }

    function updateStakePoolManager(address _stakePoolManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(StakePoolManager, _stakePoolManager);
    }

    function updatePermissionlessPool(address _permissionlessPool) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(PermissionlessPool, _permissionlessPool);
    }

    function updateUserWithdrawManager(address _userWithdrawManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(UserWithdrawManager, _userWithdrawManager);
    }

    function updatePermissionedNodeRegistry(address _permissionedNodeRegistry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setContract(PermissionedNodeRegistry, _permissionedNodeRegistry);
    }

    function updatePermissionlessNodeRegistry(address _permissionlessNodeRegistry)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setContract(PermissionlessNodeRegistry, _permissionlessNodeRegistry);
    }

    function updatePermissionedSocializingPool(address _permissionedSocializePool)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setContract(PermissionedSocializingPool, _permissionedSocializePool);
    }

    function updatePermissionlessSocializingPool(address _permissionlessSocializePool)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _setContract(PermissionlessSocializingPool, _permissionlessSocializePool);
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
        return variablesMap[SocializingPoolCycleDuration];
    }

    function getSocializingPoolCoolingPeriod() external view override returns (uint256) {
        return 2 * getSocializingPoolCycleDuration();
    }

    function getRewardsThreshold() external view override returns (uint256) {
        return variablesMap[RewardsThreshold];
    }

    function getMinDepositAmount() public view override returns (uint256) {
        return variablesMap[MinDepositAmount];
    }

    function getMaxDepositAmount() public view override returns (uint256) {
        return variablesMap[MaxDepositAmount];
    }

    function getMinWithdrawAmount() public view override returns (uint256) {
        return variablesMap[MinWithdrawAmount];
    }

    function getMaxWithdrawAmount() public view override returns (uint256) {
        return variablesMap[MaxWithdrawAmount];
    }

    function getMinDelayToFinalizeWithdrawRequest() external view override returns (uint256) {
        return variablesMap[MIN_DELAY_TO_FINALIZE_WITHDRAW_REQUEST];
    }

    //Account Getters

    function getAdmin() public view returns (address) {
        return accountsMap[Admin];
    }

    function getStaderTreasury() external view override returns (address) {
        return accountsMap[StaderTreasury];
    }

    function getStaderPenaltyFund() external view override returns (address) {
        return accountsMap[StaderPenaltyFund];
    }

    //Contracts Getters

    function getTWAPGetter() external view override returns (address) {
        return contractsMap[TWAPGetter];
    }

    function getPoolFactory() external view override returns (address) {
        return contractsMap[PoolFactory];
    }

    function getPoolSelector() external view override returns (address) {
        return contractsMap[PoolSelector];
    }

    function getPriceFetcher() external view override returns (address) {
        return contractsMap[PriceFetcher];
    }

    function getSDCollateral() external view override returns (address) {
        return contractsMap[SDCollateral];
    }

    function getVaultFactory() external view override returns (address) {
        return contractsMap[VaultFactory];
    }

    function getStaderOracle() external view override returns (address) {
        return contractsMap[StaderOracle];
    }

    function getAuctionContract() external view override returns (address) {
        return contractsMap[AuctionContract];
    }

    function getPenaltyContract() external view override returns (address) {
        return contractsMap[PenaltyContract];
    }

    function getPermissionedPool() external view override returns (address) {
        return contractsMap[PermissionedPool];
    }

    function getStakePoolManager() external view override returns (address) {
        return contractsMap[StakePoolManager];
    }

    function getETHDepositContract() external view override returns (address) {
        return contractsMap[ETHDepositContract];
    }

    function getPermissionlessPool() external view override returns (address) {
        return contractsMap[PermissionlessPool];
    }

    function getUserWithdrawManager() external view override returns (address) {
        return contractsMap[UserWithdrawManager];
    }

    function getPermissionedNodeRegistry() external view override returns (address) {
        return contractsMap[PermissionedNodeRegistry];
    }

    function getPermissionlessNodeRegistry() external view override returns (address) {
        return contractsMap[PermissionlessNodeRegistry];
    }

    function getPermissionedSocializingPool() external view override returns (address) {
        return contractsMap[PermissionedSocializingPool];
    }

    function getPermissionlessSocializingPool() external view override returns (address) {
        return contractsMap[PermissionlessSocializingPool];
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
