// File: contracts/Stader.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract StaderValidatorRegistry is Initializable, OwnableUpgradeable{

    address staderSSVStakePool;
    address staderManagedStakePool;
    uint256 public validatorCount;

    /// @notice event emits after adding a validator to validatorRegistry
    event addedToValidatorRegistry(bytes publicKey, uint256 count);

    /// @notice zero address check modifier
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), "Address cannot be zero");
        _;
    }

    /// @notice zero address check modifier
    modifier onlyPool() {
        require(msg.sender== staderSSVStakePool || msg.sender== staderManagedStakePool, "Not a pool address");
        _;
    }

    struct Validator{
        bytes pubKey; //public Key of the validator
        bytes withdrawal_credentials; //public key for withdraw
        bytes signature; //signature for deposit to Ethereum Deposit contract
        bytes32 deposit_data_root; //deposit data root for deposit to Ethereum Deposit contract
        bool depositStatus; //Deposit Status indicates wheather 32ETh deposited for that validator
    }
    mapping (uint256 => Validator) public validatorRegistry;

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize() external initializer{
        __Ownable_init_unchained();
        validatorCount=0;
    }
    
    /**
     * @dev add a validator to the registry
     * @param _pubKey public Key of the validator
     * @param _withdrawal_credentials public key for withdraw
     * @param _signature signature for deposit to Ethereum Deposit contract
     * @param _deposit_data_root deposit data root for deposit to Ethereum Deposit contract
     */
    function addToValidatorRegistry(
        bytes memory _pubKey,
        bytes memory _withdrawal_credentials,
        bytes memory _signature,
        bytes32 _deposit_data_root
    ) public onlyPool {
        Validator storage _validatorRegistry = validatorRegistry[
            validatorCount
        ];
        _validatorRegistry.pubKey = _pubKey;
        _validatorRegistry.withdrawal_credentials = _withdrawal_credentials;
        _validatorRegistry.signature = _signature;
        _validatorRegistry.deposit_data_root = _deposit_data_root;
        _validatorRegistry.depositStatus = false;
        emit addedToValidatorRegistry(_pubKey, validatorCount);
        validatorCount++;
    }

    /**
     * @notice set stader ssv stake pool address
     * @param _staderSSVStakePool address of staderSSVStakePool
     */
    function setstaderSSVStakePoolAddress(address _staderSSVStakePool) external checkZeroAddress(_staderSSVStakePool) onlyOwner{
        staderSSVStakePool = _staderSSVStakePool;
    }

    /**
     * @notice set stader managed stake pool address
     * @param _staderManagedStakePool address of staderManagedStakePool
     */
    function setstaderManagedStakePoolAddress(address _staderManagedStakePool) external checkZeroAddress(_staderManagedStakePool) onlyOwner{
        staderManagedStakePool = _staderManagedStakePool;
    }
}