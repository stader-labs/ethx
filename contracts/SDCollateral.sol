// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/AddressLib.sol';

import '../contracts/interfaces/IPoolFactory.sol';
import '../contracts/interfaces/IStaderConfig.sol';
import '../contracts/interfaces/SDCollateral/ISDCollateral.sol';
import '../contracts/interfaces/SDCollateral/IAuction.sol';
import '../contracts/interfaces/IStaderOracle.sol';

import '@openzeppelin/contracts/utils/math/Math.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract SDCollateral is
    ISDCollateral,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant MANAGER = keccak256('MANAGER');
    bytes32 public constant NODE_REGISTRY_CONTRACT = keccak256('NODE_REGISTRY_CONTRACT');

    IStaderConfig public staderConfig;
    uint256 public totalSDCollateral;
    mapping(uint8 => PoolThresholdInfo) public poolThresholdbyPoolId;
    mapping(address => uint8) private poolIdByOperator;
    mapping(address => uint256) public operatorSDBalance;

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
    }

    /**
     * @param _sdAmount SD Token Amount to Deposit
     * @dev sender should approve this contract for spending SD
     */
    function depositSDAsCollateral(uint256 _sdAmount) external {
        address operator = msg.sender;

        totalSDCollateral += _sdAmount;
        operatorSDBalance[operator] += _sdAmount;

        IERC20(staderConfig.getStaderToken()).safeTransferFrom(operator, address(this), _sdAmount);
    }

    function withdraw(uint256 _requestedSD) external {
        address operator = msg.sender;
        uint256 sdBalance = operatorSDBalance[operator];

        uint8 poolId = getOperatorPoolId(operator);
        PoolThresholdInfo storage poolThreshold = poolThresholdbyPoolId[poolId];

        // TODO: Manoj update startIndex, endIndex
        uint256 validatorCount = IPoolFactory(staderConfig.getPoolFactory()).getOperatorTotalNonTerminalKeys(
            poolId,
            operator,
            0,
            1000
        );

        uint256 sdCumulativeThreshold = convertETHToSD(poolThreshold.withdrawThreshold * validatorCount);
        if (sdBalance <= sdCumulativeThreshold) {
            revert InsufficientSDToWithdraw();
        }
        uint256 withdrawableSD = sdBalance - sdCumulativeThreshold;

        require(_requestedSD <= withdrawableSD, 'withdraw less SD');

        totalSDCollateral -= _requestedSD;
        operatorSDBalance[operator] -= _requestedSD;

        IERC20(staderConfig.getStaderToken()).safeTransfer(payable(operator), _requestedSD);
    }

    /// @notice used to slash operator SD, incase of operator default
    /// @dev do provide SD approval to auction contract using `maxApproveSD()`
    /// @param _operator which operator SD collateral to slash
    /// @param _sdToSlash amount of SD to slash
    function slashSD(address _operator, uint256 _sdToSlash) external onlyRole(MANAGER) returns (uint256 _sdSlashed) {
        uint256 sdBalance = operatorSDBalance[_operator];
        _sdSlashed = Math.min(_sdToSlash, sdBalance);
        operatorSDBalance[_operator] -= _sdSlashed;
        IAuction(staderConfig.getAuctionContract()).createLot(_sdSlashed);
    }

    /// @notice for max approval to auction contract for spending SD tokens
    /// @param spenderAddr contract to approve for spending SD
    function maxApproveSD(address spenderAddr) external onlyRole(MANAGER) {
        IERC20(staderConfig.getStaderToken()).approve(spenderAddr, type(uint256).max);
    }

    // SETTERS

    function updatePoolThreshold(
        uint8 _poolId,
        uint256 _minThreshold,
        uint256 _withdrawThreshold,
        string memory _units
    ) public onlyRole(MANAGER) {
        require(_minThreshold <= _withdrawThreshold, 'invalid limits');

        poolThresholdbyPoolId[_poolId] = PoolThresholdInfo({
            minThreshold: _minThreshold,
            withdrawThreshold: _withdrawThreshold,
            units: _units
        });
    }

    function updatePoolIdForOperator(uint8 _poolId, address _operator) public onlyRole(NODE_REGISTRY_CONTRACT) {
        AddressLib.checkNonZeroAddress(_operator);
        if (_poolId == 0) revert InvalidPoolId();
        if (bytes(poolThresholdbyPoolId[_poolId].units).length == 0) {
            revert InvalidPoolId();
        }
        poolIdByOperator[_operator] = _poolId;
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
    ) external view returns (bool) {
        return (getRemainingSDToBond(_operator, _poolId, _numValidator) == 0);
    }

    function getOperatorPoolId(address _operator) public view returns (uint8 _poolId) {
        _poolId = poolIdByOperator[_operator];
        // TODO: this check is not required as I am checking this while setting
        if (_poolId == 0) revert InvalidPoolId();
    }

    /// @notice returns minimum amount of SD required to onboard _numValidators in a pool
    /// @param _poolId pool id, where operator wants to onboard validators
    /// @param _numValidator number of validators to onBoard (including already onboarded, if any)
    function getMinimumSDToBond(uint8 _poolId, uint256 _numValidator) public view returns (uint256 _minSDToBond) {
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
    ) public view returns (uint256) {
        uint256 sdBalance = operatorSDBalance[_operator];
        uint256 minSDToBond = getMinimumSDToBond(_poolId, _numValidator);
        return (sdBalance >= minSDToBond ? 0 : minSDToBond - sdBalance);
    }

    function getMaxValidatorSpawnable(uint256 _sdAmount, uint8 _poolId) public view returns (uint256) {
        if (bytes(poolThresholdbyPoolId[_poolId].units).length == 0) {
            revert InvalidPoolId();
        }

        uint256 ethAmount = convertSDToETH(_sdAmount);
        return ethAmount / poolThresholdbyPoolId[_poolId].minThreshold;
    }

    function convertSDToETH(uint256 _sdAmount) public view returns (uint256) {
        uint256 sdPriceInETH = IStaderOracle(staderConfig.getStaderOracle()).getSDPriceInETH();
        return (_sdAmount * sdPriceInETH);
    }

    function convertETHToSD(uint256 _ethAmount) public view returns (uint256) {
        uint256 sdPriceInETH = IStaderOracle(staderConfig.getStaderOracle()).getSDPriceInETH();
        return (_ethAmount / sdPriceInETH);
    }
}
