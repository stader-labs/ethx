// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/AddressLib.sol';

import '../contracts/interfaces/IPoolFactory.sol';
import '../contracts/interfaces/SDCollateral/ISDCollateral.sol';
import '../contracts/interfaces/SDCollateral/IAuction.sol';
import '../contracts/interfaces/IStaderOracle.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract SDCollateral is
    ISDCollateral,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    bytes32 public constant MANAGER = keccak256('MANAGER');
    bytes32 public constant NODE_REGISTRY_CONTRACT = keccak256('NODE_REGISTRY_CONTRACT');

    IStaderConfig public override staderConfig;
    uint256 public override totalSDCollateral;
    mapping(uint8 => PoolThresholdInfo) public poolThresholdbyPoolId;
    mapping(address => uint256) public override operatorSDBalance;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _staderConfig) external initializer {
        AddressLib.checkNonZeroAddress(_staderConfig);

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        staderConfig = IStaderConfig(_staderConfig);
        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());

        emit UpdatedStaderConfig(_staderConfig);
    }

    /**
     * @param _sdAmount SD Token Amount to Deposit
     * @dev sender should approve this contract for spending SD
     */
    function depositSDAsCollateral(uint256 _sdAmount) external override {
        address operator = msg.sender;

        totalSDCollateral += _sdAmount;
        operatorSDBalance[operator] += _sdAmount;

        // cannot use safeERC20 as this contract is an upgradeable contract
        if (!IERC20(staderConfig.getStaderToken()).transferFrom(operator, address(this), _sdAmount)) {
            revert SDTransferFailed();
        }

        emit SDDeposited(operator, _sdAmount);
    }

    function withdraw(uint256 _requestedSD) external override {
        address operator = msg.sender;
        uint256 sdBalance = operatorSDBalance[operator];

        uint256 validatorCount = getOperatorValidatorCount(operator);
        uint8 poolId = IPoolFactory(staderConfig.getPoolFactory()).getOperatorPoolId(operator);
        PoolThresholdInfo storage poolThreshold = poolThresholdbyPoolId[poolId];

        uint256 sdCumulativeThreshold = convertETHToSD(poolThreshold.withdrawThreshold * validatorCount);
        if (sdBalance <= sdCumulativeThreshold) {
            revert InsufficientSDCollateral(sdBalance);
        }
        uint256 withdrawableSD = sdBalance - sdCumulativeThreshold;

        if (_requestedSD > withdrawableSD) {
            revert InsufficientWithdrawableSD(withdrawableSD);
        }

        totalSDCollateral -= _requestedSD;
        operatorSDBalance[operator] -= _requestedSD;

        // cannot use safeERC20 as this contract is an upgradeable contract
        if (!IERC20(staderConfig.getStaderToken()).transfer(payable(operator), _requestedSD)) {
            revert SDTransferFailed();
        }

        emit SDWithdraw(operator, _requestedSD);
    }

    /// @notice slashes one validator equi. SD amount
    /// @param _operator which operator's validator SD collateral to slash
    function slashValidatorSD(address _operator) external override onlyRole(MANAGER) returns (uint256 _sdSlashed) {
        uint256 sdBalance = operatorSDBalance[_operator];
        uint256 validatorCount = getOperatorValidatorCount(_operator);
        uint256 sdToSlash = sdBalance / validatorCount;
        // TODO: Sanjay, Dheraj Does validatorCount decreses on slashing?
        // else it will be a problem on next validator slash
        return slashSD(_operator, sdToSlash);
    }

    /// @notice used to slash operator SD, incase of operator default
    /// @dev do provide SD approval to auction contract using `maxApproveSD()`
    /// @param _operator which operator SD collateral to slash
    /// @param _sdToSlash amount of SD to slash
    function slashSD(address _operator, uint256 _sdToSlash)
        public
        override
        onlyRole(MANAGER)
        returns (uint256 _sdSlashed)
    {
        uint256 sdBalance = operatorSDBalance[_operator];
        _sdSlashed = Math.min(_sdToSlash, sdBalance);
        operatorSDBalance[_operator] -= _sdSlashed;
        IAuction(staderConfig.getAuctionContract()).createLot(_sdSlashed);

        emit SDSlashed(_operator, staderConfig.getAuctionContract(), _sdToSlash);
    }

    /// @notice for max approval to auction contract for spending SD tokens
    /// @param spenderAddr contract to approve for spending SD
    function maxApproveSD(address spenderAddr) external override onlyRole(MANAGER) {
        IERC20(staderConfig.getStaderToken()).approve(spenderAddr, type(uint256).max);
    }

    // SETTERS
    function updateStaderConfig(address _staderConfig) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        AddressLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    function updatePoolThreshold(
        uint8 _poolId,
        uint256 _minThreshold,
        uint256 _withdrawThreshold,
        string memory _units
    ) public override onlyRole(MANAGER) {
        if (_minThreshold > _withdrawThreshold) {
            revert InvalidPoolLimit();
        }

        poolThresholdbyPoolId[_poolId] = PoolThresholdInfo({
            minThreshold: _minThreshold,
            withdrawThreshold: _withdrawThreshold,
            units: _units
        });

        emit UpdatedPoolThreshold(_poolId, _minThreshold, _withdrawThreshold);
    }

    // GETTERS

    /// @notice checks if operator has enough SD collateral to onboard validators in a specific pool
    /// @param _operator node operator addr who want to onboard validators
    /// @param _poolId pool id, where operator wants to onboard validators
    /// @param _numValidator number of validators to onBoard
    function hasEnoughSDCollateral(
        address _operator,
        uint8 _poolId,
        uint256 _numValidator
    ) external view override returns (bool) {
        return (getRemainingSDToBond(_operator, _poolId, _numValidator) == 0);
    }

    /// @notice returns minimum amount of SD required to onboard _numValidators in a pool
    /// @param _poolId pool id, where operator wants to onboard validators
    /// @param _numValidator number of validators to onBoard (including already onboarded, if any)
    function getMinimumSDToBond(uint8 _poolId, uint256 _numValidator)
        public
        view
        override
        returns (uint256 _minSDToBond)
    {
        if (bytes(poolThresholdbyPoolId[_poolId].units).length == 0) {
            revert InvalidPoolId();
        }
        PoolThresholdInfo storage poolThresholdInfo = poolThresholdbyPoolId[_poolId];

        _minSDToBond = convertETHToSD(poolThresholdInfo.minThreshold);
        _minSDToBond *= _numValidator;
    }

    /// @notice returns remaining amount of SD required to onboard _numValidators
    /// @param _operator node operator addr who want to onboard validators
    /// @param _poolId pool id, where operator wants to onboard validators
    /// @param _numValidator number of validators to onBoard (including already onboarded, if any)
    function getRemainingSDToBond(
        address _operator,
        uint8 _poolId,
        uint256 _numValidator
    ) public view override returns (uint256) {
        uint256 sdBalance = operatorSDBalance[_operator];
        uint256 minSDToBond = getMinimumSDToBond(_poolId, _numValidator);
        return (sdBalance >= minSDToBond ? 0 : minSDToBond - sdBalance);
    }

    function getMaxValidatorSpawnable(uint256 _sdAmount, uint8 _poolId) external view override returns (uint256) {
        if (bytes(poolThresholdbyPoolId[_poolId].units).length == 0) {
            revert InvalidPoolId();
        }

        uint256 ethAmount = convertSDToETH(_sdAmount);
        return ethAmount / poolThresholdbyPoolId[_poolId].minThreshold;
    }

    function convertSDToETH(uint256 _sdAmount) public view override returns (uint256) {
        uint256 sdPriceInETH = IStaderOracle(staderConfig.getStaderOracle()).getSDPriceInETH();
        return (_sdAmount * sdPriceInETH);
    }

    function convertETHToSD(uint256 _ethAmount) public view override returns (uint256) {
        uint256 sdPriceInETH = IStaderOracle(staderConfig.getStaderOracle()).getSDPriceInETH();
        return (_ethAmount / sdPriceInETH);
    }

    // HELPER

    function getOperatorValidatorCount(address operator) internal view returns (uint256 _validatorCount) {
        uint8 poolId = IPoolFactory(staderConfig.getPoolFactory()).getOperatorPoolId(operator);

        INodeRegistry nodeRegistry = INodeRegistry(IPoolFactory(staderConfig.getPoolFactory()).getNodeRegistry(poolId));
        uint256 operatorId = nodeRegistry.operatorIDByAddress(operator);
        _validatorCount = IPoolFactory(staderConfig.getPoolFactory()).getOperatorTotalNonTerminalKeys(
            poolId,
            operator,
            0,
            nodeRegistry.getOperatorTotalKeys(operatorId)
        );
    }
}
