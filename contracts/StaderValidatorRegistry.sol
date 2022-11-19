// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract StaderValidatorRegistry is
    Initializable,
    AccessControlUpgradeable
{
    address public staderSSVStakePool;
    address public staderManagedStakePool;
    uint256 public validatorCount;

    bytes32 public constant POOL_OPERATOR = keccak256("POOL_OPERATOR");
    bytes32 public constant VALIDATOR_REGISTRY_ADMIN_ROLE = keccak256("VALIDATOR_REGISTRY_ADMIN_ROLE");

    /// @notice event emits after adding a validator to validatorRegistry
    event AddedToValidatorRegistry(bytes publicKey, uint256 count);

    struct Validator {
        bytes pubKey; //public Key of the validator
        bytes withdrawalCredentials; //public key for withdraw
        bytes signature; //signature for deposit to Ethereum Deposit contract
        bytes32 depositDataRoot; //deposit data root for deposit to Ethereum Deposit contract
    }
    mapping(uint256 => Validator) public validatorRegistry;
    mapping(bytes => uint256) public validatorPubKeyIndex;

    /// @notice zero address check modifier
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), "Address cannot be zero");
        _;
    }

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize() external initializer {
        __AccessControl_init_unchained();
        _grantRole(VALIDATOR_REGISTRY_ADMIN_ROLE,msg.sender);
    }

    /**
     * @notice set stader ssv stake pool address
     * @param _staderSSVStakePool address of staderSSVStakePool
     */
    function setStaderSSVStakePoolAddress(address _staderSSVStakePool)
        external
        checkZeroAddress(_staderSSVStakePool)
        onlyRole(VALIDATOR_REGISTRY_ADMIN_ROLE)
    {
        if(hasRole(POOL_OPERATOR,staderSSVStakePool)) _revokeRole(POOL_OPERATOR,staderSSVStakePool);
        staderSSVStakePool = _staderSSVStakePool;
        _grantRole(POOL_OPERATOR,staderSSVStakePool);
    }

    /**
     * @notice set stader managed stake pool address
     * @param _staderManagedStakePool address of staderManagedStakePool
     */
    function setStaderManagedStakePoolAddress(address _staderManagedStakePool)
        external
        checkZeroAddress(_staderManagedStakePool)
        onlyRole(VALIDATOR_REGISTRY_ADMIN_ROLE)
    {
        if(hasRole(POOL_OPERATOR,staderManagedStakePool)) _revokeRole(POOL_OPERATOR,staderManagedStakePool);
        staderManagedStakePool = _staderManagedStakePool;
        _grantRole(POOL_OPERATOR,staderManagedStakePool);
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
    ) external onlyRole(POOL_OPERATOR) {
        Validator storage _validatorRegistry = validatorRegistry[
            validatorCount
        ];
        _validatorRegistry.pubKey = _pubKey;
        _validatorRegistry.withdrawalCredentials = _withdrawalCredentials;
        _validatorRegistry.signature = _signature;
        _validatorRegistry.depositDataRoot = _depositDataRoot;
        validatorPubKeyIndex[_pubKey] = validatorCount;
        validatorCount++;
        emit AddedToValidatorRegistry(_pubKey, validatorCount);
    }

    function getPoRAddressListLength()
        external
        view
        returns (uint256)
    {
        return validatorCount;
    }

    function getPoRAddressList(uint256 startIndex, uint256 endIndex)
        external
        view
        returns (string[] memory)
    {
        if (startIndex > endIndex) {
            return new string[](0);
        }
        endIndex = endIndex > validatorCount - 1
            ? validatorCount - 1
            : endIndex;
        string[] memory stringAddresses = new string[](
            endIndex - startIndex + 1
        );
        uint256 currIdx = startIndex;
        uint256 strAddrIdx = 0;
        while (currIdx <= endIndex) {
            stringAddresses[strAddrIdx] = toString(
                abi.encodePacked(validatorRegistry[currIdx].pubKey)
            );
            strAddrIdx++;
            currIdx++;
        }
        return stringAddresses;
    }

    function getValidatorIndexByPublicKey(bytes memory _publicKey)
        public
        view
        returns (uint256)
    {
        uint256 index = validatorPubKeyIndex[_publicKey];
        if (keccak256(_publicKey) == keccak256(validatorRegistry[index].pubKey))
            return index;
        return type(uint256).max;
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
