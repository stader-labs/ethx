// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IPoRAddressList.sol";

contract StaderValidatorRegistry is
    Initializable,
    OwnableUpgradeable,
    IPoRAddressList
{
    address public staderSSVStakePool;
    address public staderManagedStakePool;
    uint256 public validatorCount;

    /// @notice event emits after adding a validator to validatorRegistry
    event AddedToValidatorRegistry(bytes publicKey, uint256 count);

    struct Validator {
        bytes pubKey; //public Key of the validator
        bytes withdrawalCredentials; //public key for withdraw
        bytes signature; //signature for deposit to Ethereum Deposit contract
        bytes32 depositDataRoot; //deposit data root for deposit to Ethereum Deposit contract
        bool depositStatus; //Deposit Status indicates whether 32ETh deposited for that validator
    }
    mapping(uint256 => Validator) public validatorRegistry;
    mapping(bytes => uint256) public validatorPubKeyIndex;

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

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize() external initializer {
        __Ownable_init_unchained();
    }

    /**
     * @dev add a validator to the registry
     * @param _pubKey public Key of the validator
     * @param _withdrawalCredentials public key for withdraw
     * @param _signature signature for deposit to Ethereum Deposit contract
     * @param _depositDataRoot deposit data root for deposit to Ethereum Deposit contract
     */
    function addToValidatorRegistry(
        bytes memory _pubKey,
        bytes memory _withdrawalCredentials,
        bytes memory _signature,
        bytes32 _depositDataRoot
    ) external onlyPool {
        Validator storage _validatorRegistry = validatorRegistry[
            validatorCount
        ];
        _validatorRegistry.pubKey = _pubKey;
        _validatorRegistry.withdrawalCredentials = _withdrawalCredentials;
        _validatorRegistry.signature = _signature;
        _validatorRegistry.depositDataRoot = _depositDataRoot;
        _validatorRegistry.depositStatus = true;
        validatorPubKeyIndex[_pubKey] = validatorCount;
        validatorCount++;
        emit AddedToValidatorRegistry(_pubKey, validatorCount);
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
        for (uint256 i = 0; i < validatorCount; i++) {
            bytesAddresses[i] = toString(validatorRegistry[i].pubKey);
        }
        return bytesAddresses;
    }

    function getValidatorIndexByPublicKey(bytes memory _publicKey)
        public
        view
        returns (uint256)
    {
        if (validatorPubKeyIndex[_publicKey]!=0){
            return validatorPubKeyIndex[_publicKey];
        }
        else{
            if(keccak256(_publicKey) == keccak256(validatorRegistry[0].pubKey)) return 0;
            else return type(uint256).max;
        }
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
