// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./interfaces/ISSVNetwork.sol";
import "./interfaces/IDepositContract.sol";
import "./interfaces/IStaderSSVStakePool.sol";
import "./interfaces/IStaderValidatorRegistry.sol";

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/**
 * @notice Staking pool implementation on top of SSV Technology
 * Secret Shared Validator (SSV) technology is the first secure and robust way
 * to split a validator key for ETH staking between non-trusting nodes run by operators.
 * It is a unique protocol that enables the distributed operation of an Ethereum validator.
 */

contract StaderSSVStakePool is
    IStaderSSVStakePool,
    Initializable,
    AccessControlUpgradeable
{
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    ISSVNetwork public ssvNetwork;
    IERC20 public ssvToken;
    IDepositContract public ethValidatorDeposit;
    IStaderValidatorRegistry public staderValidatorRegistry;
    uint256 public staderSSVRegistryCount;

    bytes32 public constant SSV_POOL_ADMIN_ROLE = keccak256("SSV_POOL_ADMIN_ROLE");

    /**
     * @dev Validator registry structure
     */
    struct ValidatorShares {
        bytes pubKey; ///public Key of the validator
        uint32[] operatorIDs; ///operator IDs of operator assigned to a validator
        bytes[] publicShares; ///public shares for operators of a validator
        bytes[] encryptedShares; ///encrypt shares for operators of a validator
    }

    /// @notice Validator Registry mapping
    mapping(uint256 => ValidatorShares) public staderSSVRegistry;
    mapping(bytes => uint256) public ssvValidatorPubKeyIndex;

    /// @notice zero address check modifier
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), "Address cannot be zero");
        _;
    }

    /**
     * @dev SSV Staking Pool is initialized with following variables
     * @param _ssvNetwork SSV Network Contract
     * @param _ssvToken SSV Token Contract
     * @param _ethValidatorDeposit ethereum Deposit contract
     */
    function initialize(
        address _ssvNetwork,
        address _ssvToken,
        address _ethValidatorDeposit,
        address _staderValidatorRegistry,
        address _ssvPoolAdmin
    )
        external
        initializer
        checkZeroAddress(_ssvNetwork)
        checkZeroAddress(_ssvToken)
        checkZeroAddress(_ethValidatorDeposit)
        checkZeroAddress(_staderValidatorRegistry)
        checkZeroAddress(_ssvPoolAdmin)
    {
        __AccessControl_init_unchained();
        _grantRole(SSV_POOL_ADMIN_ROLE,_ssvPoolAdmin);
        ssvNetwork = ISSVNetwork(_ssvNetwork);
        ssvToken = IERC20(_ssvToken);
        ethValidatorDeposit = IDepositContract(_ethValidatorDeposit);
        staderValidatorRegistry = IStaderValidatorRegistry(
            _staderValidatorRegistry
        );
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev stader pool manager send ETH to stader SSV stake pool
     */
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }

    /**
     * @dev update the SSV Network contract
     * @param _ssvNetwork ssv Network contract
     */
    function updateSSVNetworkAddress(address _ssvNetwork)
        external
        checkZeroAddress(_ssvNetwork)
        onlyRole(SSV_POOL_ADMIN_ROLE)
    {
        ssvNetwork = ISSVNetwork(_ssvNetwork);
    }

    /**
     * @dev update the Eth Deposit contract
     * @param _ethValidatorDeposit  Eth Deposit contract
     */
    function updateEthDepositAddress(address _ethValidatorDeposit)
        external
        checkZeroAddress(_ethValidatorDeposit)
        onlyRole(SSV_POOL_ADMIN_ROLE)
    {
        ethValidatorDeposit = IDepositContract(_ethValidatorDeposit);
    }

    /**
     * @dev update the SSV Token contract
     * @param _ssvToken  SSV Token contract
     */
    function updateSSVTokenAddress(address _ssvToken)
        external
        checkZeroAddress(_ssvToken)
        onlyRole(SSV_POOL_ADMIN_ROLE)
    {
        ssvToken = IERC20(_ssvToken);
    }

    /**
     * @dev register a Validator to SSV Network
     * @param tokenFees ssv token as network and operators fee
     */
    function registerValidatorToSSVNetwork(
        bytes memory _pubKey,
        bytes[] memory _publicShares,
        bytes[] memory _encryptedShares,
        uint32[] memory _operatorIDs,
        uint256 tokenFees
    ) external onlyRole(SSV_POOL_ADMIN_ROLE) {
        require(
            _publicShares.length == _encryptedShares.length &&
                _encryptedShares.length == _operatorIDs.length,
            "invalid parameters"
        );
        ssvToken.approve(address(ssvNetwork), tokenFees);
        ssvNetwork.registerValidator(
            _pubKey,
            _operatorIDs,
            _publicShares,
            _encryptedShares,
            tokenFees
        );
        _addToStaderSSVRegistry(
            _pubKey,
            _publicShares,
            _encryptedShares,
            _operatorIDs
        );
        emit RegisteredValidatorToSSVNetwork(_pubKey);
    }

    function updateValidatorToSSVNetwork(
        bytes memory _pubKey,
        bytes[] memory _publicShares,
        bytes[] memory _encryptedShares,
        uint32[] memory _operatorIDs,
        uint256 tokenFees
    ) external onlyRole(SSV_POOL_ADMIN_ROLE) {
        require(
            _publicShares.length == _encryptedShares.length &&
                _encryptedShares.length == _operatorIDs.length,
            "invalid parameters"
        );
        ssvToken.approve(address(ssvNetwork), tokenFees);
        uint256 index = getValidatorIndexByPublicKey(_pubKey);
        require(index < staderSSVRegistryCount, "validator not registered");

        ssvNetwork.updateValidator(
            _pubKey,
            _operatorIDs,
            _publicShares,
            _encryptedShares,
            tokenFees
        );
        staderSSVRegistry[index].operatorIDs = _operatorIDs;
        staderSSVRegistry[index].publicShares = _publicShares;
        staderSSVRegistry[index].encryptedShares = _encryptedShares;

        emit UpdatedValidatorToSSVNetwork(
            staderSSVRegistry[index].pubKey,
            index
        );
    }

    function removeValidatorFromSSVNetwork(bytes calldata publicKey)
        external
        onlyRole(SSV_POOL_ADMIN_ROLE)
    {
        uint256 index = getValidatorIndexByPublicKey(publicKey);
        require(index < staderSSVRegistryCount, "validator not registered");

        ssvNetwork.removeValidator(publicKey);
        delete (staderSSVRegistry[index]);
        staderSSVRegistryCount--;

        emit RemovedValidatorFromSSVNetwork(publicKey, index);
    }

    /// @dev deposit 32 ETH in ethereum deposit contract
    function depositEthToDepositContract(
        bytes calldata pubKey,
        bytes calldata withdrawalCredentials,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external onlyRole(SSV_POOL_ADMIN_ROLE) {
        require(
            address(this).balance >= DEPOSIT_SIZE,
            "not enough balance to deposit"
        );
        ethValidatorDeposit.deposit{value: DEPOSIT_SIZE}(
            pubKey,
            withdrawalCredentials,
            signature,
            depositDataRoot
        );
        staderValidatorRegistry.addToValidatorRegistry(
            pubKey,
            withdrawalCredentials,
            signature,
            depositDataRoot
        );
        emit DepositToDepositContract(pubKey);
    }

    function getValidatorIndexByPublicKey(bytes memory _publicKey)
        public
        view
        returns (uint256)
    {
        uint256 index = ssvValidatorPubKeyIndex[_publicKey];
        if (keccak256(_publicKey) == keccak256(staderSSVRegistry[index].pubKey))
            return index;
        return type(uint256).max;
    }

    /**
     * @dev add a validator to the registry
     * @param _pubKey public Key of the validator
     * @param _publicShares public shares for operators of a validator
     * @param _encryptedShares encrypt shares for operators of a validator
     * @param _operatorIDs operator IDs of operator assigned to a validator
     */
    function _addToStaderSSVRegistry(
        bytes memory _pubKey,
        bytes[] memory _publicShares,
        bytes[] memory _encryptedShares,
        uint32[] memory _operatorIDs
    ) internal {
        ValidatorShares storage _staderSSVRegistry = staderSSVRegistry[
            staderSSVRegistryCount
        ];
        _staderSSVRegistry.pubKey = _pubKey;
        _staderSSVRegistry.publicShares = _publicShares;
        _staderSSVRegistry.encryptedShares = _encryptedShares;
        _staderSSVRegistry.operatorIDs = _operatorIDs;
        ssvValidatorPubKeyIndex[_pubKey] = staderSSVRegistryCount;
        staderSSVRegistryCount++;
        emit AddedToStaderSSVRegistry(_pubKey, staderSSVRegistryCount);
    }
}
