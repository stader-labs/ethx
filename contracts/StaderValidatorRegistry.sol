// File: contracts/StaderValidatorRegistry.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/IPoRAddressList.sol";

contract StaderValidatorRegistry is Initializable, OwnableUpgradeable, IPoRAddressList {
    address public staderSSVStakePool ;
    address public staderManagedStakePool;
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
        require(
            msg.sender == staderSSVStakePool ||
                msg.sender == staderManagedStakePool,
            "Not a pool address"
        );
        _;
    }

    struct Validator {
        bytes pubKey; //public Key of the validator
        bytes withdrawal_credentials; //public key for withdraw
        bytes signature; //signature for deposit to Ethereum Deposit contract
        bytes32 deposit_data_root; //deposit data root for deposit to Ethereum Deposit contract
        bool depositStatus; //Deposit Status indicates whether 32ETh deposited for that validator
    }
    mapping(uint256 => Validator) public validatorRegistry;

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize()external initializer {
        __Ownable_init_unchained();
        validatorCount = 0;
        staderManagedStakePool = address(0);
        staderSSVStakePool = address(0);
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
        _validatorRegistry.depositStatus = true;
        validatorCount++;
        emit addedToValidatorRegistry(_pubKey, validatorCount);
    }

    /**
     * @notice set stader ssv stake pool address
     * @param _staderSSVStakePool address of staderSSVStakePool
     */
    function setStaderSSVStakePoolAddress(address _staderSSVStakePool)
        external
        checkZeroAddress(_staderSSVStakePool)
        onlyOwner
    {
        staderSSVStakePool = _staderSSVStakePool;
    }

    /**
     * @notice set stader managed stake pool address
     * @param _staderManagedStakePool address of staderManagedStakePool
     */
    function setStaderManagedStakePoolAddress(address _staderManagedStakePool)
        external
        checkZeroAddress(_staderManagedStakePool)
        onlyOwner
    {
        staderManagedStakePool = _staderManagedStakePool;
    }

    function getValidatorIndexByPublicKey(bytes memory _publicKey)
        public
        view
        returns (uint256)
    {
        for (uint256 i = 0; i < validatorCount; i++) {
            if (
                keccak256(_publicKey) == keccak256(validatorRegistry[i].pubKey)
            ) {
                return i;
            }
        }
        return type(uint256).max;
    }

    function getPoRAddressListLength()
        external
        view
        override
        returns (uint256)
    {
        return validatorCount;
    }

    function getPoRAddressList()
        external
        view
        override
        returns (string[] memory)
    {
        string[] memory bytesAddresses = new string[](validatorCount);
        for(uint256 i=0; i<validatorCount;i++){
            bytesAddresses[i] = toString(validatorRegistry[i].pubKey);
        }
        return bytesAddresses;
    }

    function toString(bytes memory data) private pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[3 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }

}
