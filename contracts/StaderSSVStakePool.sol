// File: contracts/StaderSSVStakePool.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2.0;

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
    ISSVNetwork public ssvNetwork;
    IERC20 public ssvToken;
    IDepositContract public ethValidatorDeposit;
    IStaderValidatorRegistry public staderValidatorRegistry;
    uint256 public staderSSVRegistryCount;

    /// @notice validator is added to on chain registry
    event addedToStaderSSVRegistry(bytes indexed pubKey, uint256 index);

    /// @notice validator is added to SSV Network
    event registeredValidatorToSSVNetwork(bytes indexed pubKey);

    /// @notice event emits after updating operators for a validator
    event updatedValidatorToSSVNetwork(bytes indexed pubKey, uint256 index);

    /// @notice event emits after removing validator from SSV
    event removedValidatorFromSSVNetwork(bytes indexed pubKey, uint256 index);

    /// @notice Deposited in Ethereum Deposit contract
    event depositToDepositContract(bytes indexed pubKey);

    /// event emits after receiving ETH from stader stake pool manager
    event receivedFromPoolManager(address indexed from, uint256 amount);

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
        ISSVNetwork _ssvNetwork,
        IERC20 _ssvToken,
        IDepositContract _ethValidatorDeposit,
        IStaderValidatorRegistry _staderValidatorRegistry
    )
        external
        initializer
        checkZeroAddress(address(_ssvNetwork))
        checkZeroAddress(address(_ssvToken))
        checkZeroAddress(address(_ethValidatorDeposit))
        checkZeroAddress(address(_staderValidatorRegistry))
    {
        __Ownable_init_unchained();
        ssvNetwork = _ssvNetwork;
        ssvToken = _ssvToken;
        ethValidatorDeposit = _ethValidatorDeposit;
        staderValidatorRegistry = _staderValidatorRegistry;
        ssvToken.approve(address(ssvNetwork), type(uint256).max);
        staderSSVRegistryCount = 0;
    }

    /**
     * @dev add a validator to the registry
     * @param _pubKey public Key of the validator
     * @param _publicShares public shares for operators of a validator
     * @param _encryptedShares encrypt shares for operators of a validator
     * @param _operatorIDs operator IDs of operator assigned to a validator
     */
    function addToStaderSSVRegistry(
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
        staderSSVRegistryCount++;
        emit addedToStaderSSVRegistry(_pubKey, staderSSVRegistryCount);
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
        ssvNetwork.registerValidator(
            _pubKey,
            _operatorIDs,
            _publicShares,
            _encryptedShares,
            tokenFees
        );
        addToStaderSSVRegistry(
            _pubKey,
            _publicShares,
            _encryptedShares,
            _operatorIDs
        );
        emit registeredValidatorToSSVNetwork(_pubKey);
    }

    function updateValidatorToSSVNetwork(
        bytes memory _pubKey,
        bytes[] memory _publicShares,
        bytes[] memory _encryptedShares,
        uint32[] memory _operatorIDs,
        uint256 tokenFees
    ) external onlyOwner {
        uint256 index = getValidatorIndexByPublicKey(_pubKey);
        require(
            index < staderSSVRegistryCount,
            "validator not registered"
        );

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

        emit updatedValidatorToSSVNetwork(
            staderSSVRegistry[index].pubKey,
            index
        );
    }

    function removeValidatorFromSSVNetwork(bytes calldata publicKey)
        external
        onlyOwner
    {
        uint256 index = getValidatorIndexByPublicKey(publicKey);
        require(
            index < staderSSVRegistryCount,
            "invalid index"
        );

        ssvNetwork.removeValidator(publicKey);
        delete (staderSSVRegistry[index]);
        staderSSVRegistryCount--;

        emit removedValidatorFromSSVNetwork(publicKey, index);
    }

    function getValidatorIndexByPublicKey(bytes memory _publicKey)
        public
        view
        returns (uint256)
    {
        for (uint256 i = 0; i < staderSSVRegistryCount; i++) {
            if (
                keccak256(_publicKey) == keccak256(staderSSVRegistry[i].pubKey)
            ) {
                return i;
            }
        }
        return type(uint256).max;
    }

    /// @dev deposit 32 ETH in ethereum deposit contract
    function depositEthToDepositContract(
        bytes calldata pubKey,
        bytes calldata withdrawalCredentials,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external onlyOwner {
        require(
            address(this).balance >= 32 ether,
            "not enough balance to deposit"
        );
        // ethValidatorDeposit.deposit{value: 32 ether}(
        //     pubKey,
        //     withdrawal_credentials,
        //     signature,
        //     deposit_data_root
        // );
        staderValidatorRegistry.addToValidatorRegistry(
            pubKey,
            withdrawalCredentials,
            signature,
            depositDataRoot
        );
        emit depositToDepositContract(pubKey);
    }

    /**
     * @dev update the SSV Network contract
     * @param _ssvNetwork ssv Network contract
     */
    function updateSSVNetworkAddress(ISSVNetwork _ssvNetwork)
        external
        checkZeroAddress(address(_ssvNetwork))
        onlyOwner
    {
        ssvNetwork = _ssvNetwork;
    }

    /**
     * @dev update the Eth Deposit contract
     * @param _ethValidatorDeposit  Eth Deposit contract
     */
    function updateEthDepositAddress(IDepositContract _ethValidatorDeposit)
        external
        checkZeroAddress(address(_ethValidatorDeposit))
        onlyOwner
    {
        ethValidatorDeposit = _ethValidatorDeposit;
    }

    /**
     * @dev update the SSV Token contract
     * @param _ssvToken  SSV Token contract
     */
    function updateSSVTokenAddress(IERC20 _ssvToken)
        external
        checkZeroAddress(address(_ssvToken))
        onlyOwner
    {
        ssvToken = _ssvToken;
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev stader pool manager send ETH to stader SSV stake pool
     */
    function receiveEthFromPoolManager() external payable {
        emit receivedFromPoolManager(msg.sender, msg.value);
    }
}
