// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./interfaces/ISSVNetwork.sol";
import "./interfaces/IDepositContract.sol";
import "./interfaces/IStaderValidatorRegistry.sol";

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @notice Staking pool implementation on top of SSV Technology
 * Secret Shared Validator (SSV) technology is the first secure and robust way
 * to split a validator key for ETH staking between non-trusting nodes run by operators.
 * It is a unique protocol that enables the distributed operation of an Ethereum validator.
 */

contract StaderSSVStakePool is Initializable, OwnableUpgradeable {
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    address public ssvNetwork;
    address public ssvToken;
    address public ethValidatorDeposit;
    address public staderValidatorRegistry;
    uint256 public staderSSVRegistryCount;

    /**
     * @dev Validator registry structure
     */
    struct ValidatorShares {
        bytes pubKey; ///public Key of the validator
        bytes[] publicShares; ///public shares for operators of a validator
        bytes[] encryptedShares; ///encrypt shares for operators of a validator
        uint32[] operatorIDs; ///operator IDs of operator assigned to a validator
    }

    /// @notice Validator Registry mapping
    mapping(uint256 => ValidatorShares) public staderSSVRegistry;
    mapping (bytes => uint256) public ssvValidatorPubKeyIndex;

    /// @notice validator is added to on chain registry
    event AddedToStaderSSVRegistry(bytes indexed pubKey, uint256 index);

    /// @notice validator is added to SSV Network
    event RegisteredValidatorToSSVNetwork(bytes indexed pubKey);

    /// @notice event emits after updating operators for a validator
    event UpdatedValidatorToSSVNetwork(bytes indexed pubKey, uint256 index);

    /// @notice event emits after removing validator from SSV
    event RemovedValidatorFromSSVNetwork(bytes indexed pubKey, uint256 index);

    /// @notice Deposited in Ethereum Deposit contract
    event DepositToDepositContract(bytes indexed pubKey);

    /// event emits after receiving ETH from stader stake pool manager
    event ReceivedETH(address indexed from, uint256 amount);

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
        address _staderValidatorRegistry
    )
        external
        initializer
        checkZeroAddress(_ssvNetwork)
        checkZeroAddress(_ssvToken)
        checkZeroAddress(_ethValidatorDeposit)
        checkZeroAddress(_staderValidatorRegistry)
    {
        __Ownable_init_unchained();
        ssvNetwork = _ssvNetwork;
        ssvToken = _ssvToken;
        ethValidatorDeposit = _ethValidatorDeposit;
        staderValidatorRegistry = _staderValidatorRegistry;
        IERC20(ssvToken).approve(address(ssvNetwork), type(uint256).max);
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev stader pool manager send ETH to stader SSV stake pool
     */
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
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
    ) external onlyOwner {
        ISSVNetwork(ssvNetwork).registerValidator(
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
    ) external onlyOwner {
        uint256 index = getValidatorIndexByPublicKey(_pubKey);
        require(index < staderSSVRegistryCount, "validator not registered");

        ISSVNetwork(ssvNetwork).updateValidator(
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
        onlyOwner
    {
        uint256 index = getValidatorIndexByPublicKey(publicKey);
        require(index < staderSSVRegistryCount, "validator not registered");

        ISSVNetwork(ssvNetwork).removeValidator(publicKey);
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
    ) external onlyOwner {
        require(
            address(this).balance >= DEPOSIT_SIZE,
            "not enough balance to deposit"
        );
        IDepositContract(ethValidatorDeposit).deposit{value: DEPOSIT_SIZE}(
            pubKey,
            withdrawalCredentials,
            signature,
            depositDataRoot
        );
        IStaderValidatorRegistry(staderValidatorRegistry)
            .addToValidatorRegistry(
                pubKey,
                withdrawalCredentials,
                signature,
                depositDataRoot
            );
        emit DepositToDepositContract(pubKey);
    }

    /**
     * @dev update the SSV Network contract
     * @param _ssvNetwork ssv Network contract
     */
    function updateSSVNetworkAddress(address _ssvNetwork)
        external
        checkZeroAddress(_ssvNetwork)
        onlyOwner
    {
        ssvNetwork = _ssvNetwork;
    }

    /**
     * @dev update the Eth Deposit contract
     * @param _ethValidatorDeposit  Eth Deposit contract
     */
    function updateEthDepositAddress(address _ethValidatorDeposit)
        external
        checkZeroAddress(_ethValidatorDeposit)
        onlyOwner
    {
        ethValidatorDeposit = _ethValidatorDeposit;
    }

    /**
     * @dev update the SSV Token contract
     * @param _ssvToken  SSV Token contract
     */
    function updateSSVTokenAddress(address _ssvToken)
        external
        checkZeroAddress(_ssvToken)
        onlyOwner
    {
        ssvToken = _ssvToken;
    }

    function getValidatorIndexByPublicKey(bytes memory _publicKey)
        public
        view
        returns (uint256)
    {
        if (ssvValidatorPubKeyIndex[_publicKey]!=0){
            return ssvValidatorPubKeyIndex[_publicKey];
        }
        else{
            if(keccak256(_publicKey) == keccak256(staderSSVRegistry[0].pubKey)) return 0;
            else return type(uint256).max;
        }
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
