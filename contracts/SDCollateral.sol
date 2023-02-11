// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';

contract SDCollateral is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct SDBalanceInfo {
        uint256 sdBalance;
        uint8 poolId;
    }

    struct PoolThresholdInfo {
        uint256 lower;
        uint256 upper;
        string units;
    }

    IERC20Upgradeable public sdERC20;
    uint256 public totalShares;
    uint256 public totalSDCollateral;
    // TODO: is this SD Collateral stored in this contract, if yes then we can instead use sdBalnce(address(this))

    mapping(address => SDBalanceInfo) public pubKeyToSDBalanceMap;
    mapping(uint8 => PoolThresholdInfo) public poolThreshold;
    mapping(address => uint256) public validatorShares;

    /**
     * @notice Check for zero address
     * @dev Modifier
     * @param _address the address to check
     */
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _sdERC20Addr,
        address _admin
    ) external initializer checkZeroAddress(_sdERC20Addr) checkZeroAddress(_admin) {
        __AccessControl_init();
        __Pausable_init();

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);

        sdERC20 = IERC20Upgradeable(_sdERC20Addr);
    }

    /**
     * @param _pubKey Unique Public Key of Validator
     * @param _sdAmount SD Token Amount to Deposit
     * @param _poolId Pool ID
     * @dev sender should approve this contract for spending SD
     */
    function depositSDAsCollateral(address _pubKey, uint256 _sdAmount, uint8 _poolId) external {
        uint256 currSDBalance = getSDBalance(_pubKey);
        uint256 newSDBalance = _sdAmount + currSDBalance;
        require(checkPoolThreshold(_poolId, newSDBalance), 'sd balance oor');

        SDBalanceInfo storage sdBalanceInfo = pubKeyToSDBalanceMap[_pubKey];
        // TODO: check if sdBalanceInfo exists, i.e. check if its a new entry
        // if new pool, add a entry,
        // else require _poolId == sdBalanceInfo.poolId

        sdBalanceInfo.sdBalance = newSDBalance;
        totalSDCollateral += _sdAmount;

        uint256 numShares = convertSDToShares(_sdAmount);
        validatorShares[_pubKey] += numShares;
        totalShares += numShares;

        sdERC20.safeTransferFrom(msg.sender, address(this), _sdAmount);
    }

    function withdraw(
        address _pubKey,
        address _recipient,
        uint256 _sdAmountToWithdraw
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        SDBalanceInfo storage sdBalanceInfo = pubKeyToSDBalanceMap[_pubKey];
        sdBalanceInfo.sdBalance -= _sdAmountToWithdraw;
        totalSDCollateral -= _sdAmountToWithdraw;

        uint256 numShares = convertSDToShares(_sdAmountToWithdraw);
        validatorShares[_pubKey] -= numShares;
        totalShares -= numShares;

        sdERC20.safeTransfer(payable(_recipient), _sdAmountToWithdraw);
    }

    function addRewards(uint256 _sdAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        totalSDCollateral += _sdAmount;
        sdERC20.safeTransferFrom(msg.sender, address(this), _sdAmount);
    }

    // SETTERS

    function updatePoolThreshold(
        uint8 _poolId,
        uint256 _lower,
        uint256 _upper,
        string memory _units
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        poolThreshold[_poolId] = PoolThresholdInfo({lower: _lower, upper: _upper, units: _units});
    }

    // GETTERS

    function hasEnoughSDCollateral(address _pubKey, uint8 _poolId) public view returns (bool) {
        uint256 sdBalance = getSDBalance(_pubKey);
        return checkPoolThreshold(_poolId, sdBalance);
    }

    // HELPER FUNCTIONS

    function checkPoolThreshold(uint8 _poolId, uint256 _sdBalance) public view returns (bool) {
        uint256 eqEthBalance = convertSDToETH(_sdBalance);
        PoolThresholdInfo storage poolThresholdInfo = poolThreshold[_poolId];
        return (eqEthBalance >= poolThresholdInfo.lower && eqEthBalance <= poolThresholdInfo.upper);
    }

    function getSDBalance(address _pubKey) public view returns (uint256) {
        SDBalanceInfo storage sdBalanceInfo = pubKeyToSDBalanceMap[_pubKey];
        return sdBalanceInfo.sdBalance;
    }

    function convertSDToETH(uint256 _sdAmount) public pure returns (uint256) {
        // TODO: fetch price from Oracle and write proper conversion logic
        return _sdAmount;
    }

    function convertETHToSD(uint256 _ethAmount) public pure returns (uint256) {
        // TODO: fetch price from Oracle and write proper conversion logic
        return _ethAmount;
    }

    function convertSDToShares(uint256 _sdAmount) public view returns (uint256) {
        uint256 totalShares_ = totalShares == 0 ? 1 : totalShares;
        uint256 totalSDCollateral_ = totalSDCollateral == 0 ? 1 : totalSDCollateral;

        return (_sdAmount * totalShares_) / totalSDCollateral_;
    }

    function convertSharesToSD(uint256 _numShares) public view returns (uint256) {
        uint256 totalShares_ = totalShares == 0 ? 1 : totalShares;
        uint256 totalSDCollateral_ = totalSDCollateral == 0 ? 1 : totalSDCollateral;

        return (_numShares * totalSDCollateral_) / totalShares_;
    }
}
