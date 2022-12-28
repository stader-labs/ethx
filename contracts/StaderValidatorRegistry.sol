// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderValidatorRegistry is Initializable, AccessControlUpgradeable {
    uint256 public validatorCount;
    uint256 public registeredValidatorCount;
    uint256 public constant collateralETH = 4 ether;

    bytes32 public constant STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');
    bytes32 public constant VALIDATOR_REGISTRY_ADMIN = keccak256('VALIDATOR_REGISTRY_ADMIN');

    /// @notice event emits after adding a validator to validatorRegistry
    event AddedToValidatorRegistry(bytes publicKey, string poolType, uint256 count);

    struct Validator {
        bool validatorDepositStatus; // state of validator
        bytes pubKey; //public Key of the validator
        bytes signature; //signature for deposit to Ethereum Deposit contract
        bytes32 depositDataRoot; //deposit data root for deposit to Ethereum Deposit contract
        string poolType; // validator pool type
        uint256 operatorId; // stader network assigned Id
        uint256 bondEth; // amount of bond eth in gwei
    }
    mapping(uint256 => Validator) public validatorRegistry;
    mapping(bytes => uint256) public validatorPubKeyIndex;

    /// @notice zero address check modifier
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize() external initializer {
        __AccessControl_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(STADER_NETWORK_POOL, msg.sender);
        _grantRole(VALIDATOR_REGISTRY_ADMIN, msg.sender);
    }

    /**
     * @dev add a validator to the registry
     * @param _validatorDepositStatus status of validator
     * @param _pubKey public Key of the validator
     * @param _signature signature for deposit to Ethereum Deposit contract
     * @param _depositDataRoot deposit data root for deposit to Ethereum Deposit contract
     * @param _poolType stader network pool type
     * @param _operatorId stader network assigned operator ID
     * @param _bondEth amount of bond eth in gwei
     */
    function addToValidatorRegistry(
        bool _validatorDepositStatus,
        bytes memory _pubKey,
        bytes memory _signature,
        bytes32 _depositDataRoot,
        string memory _poolType,
        uint256 _operatorId,
        uint256 _bondEth
    ) external onlyRole(STADER_NETWORK_POOL) {
        Validator storage _validatorRegistry = validatorRegistry[validatorCount];
        _validatorRegistry.validatorDepositStatus = _validatorDepositStatus;
        _validatorRegistry.pubKey = _pubKey;
        _validatorRegistry.signature = _signature;
        _validatorRegistry.depositDataRoot = _depositDataRoot;
        _validatorRegistry.poolType = _poolType;
        _validatorRegistry.operatorId = _operatorId;
        _validatorRegistry.bondEth = _bondEth;
        validatorPubKeyIndex[_pubKey] = validatorCount;
        validatorCount++;
        emit AddedToValidatorRegistry(_pubKey, _poolType, validatorCount);
    }

    function incrementRegisteredValidatorCount(bytes memory _pubKey) external onlyRole(STADER_NETWORK_POOL) {
        uint256 index = validatorPubKeyIndex[_pubKey];
        require(index != type(uint256).max, 'pubKey does not exist on registry');
        validatorRegistry[index].validatorDepositStatus = true;
        registeredValidatorCount++;
    }

    function getNextPermissionLessValidator() external view returns (uint256) {
        uint256 index = 0;
        while (index < validatorCount) {
            if (
                validatorRegistry[index].validatorDepositStatus == false &&
                validatorRegistry[index].bondEth == collateralETH
            ) {
                return index;
            }
            index++;
        }
        return type(uint256).max;
    }

    function getNextPermissionValidator() external view returns (uint256) {
        uint256 index = 0;
        while (index < validatorCount) {
            if (validatorRegistry[index].validatorDepositStatus == false && validatorRegistry[index].bondEth == 0) {
                return index;
            }
            index++;
        }
        return type(uint256).max;
    }

    function getPoRAddressListLength() external view returns (uint256) {
        return validatorCount;
    }

    function getPoRAddressList(uint256 startIndex, uint256 endIndex) external view returns (string[] memory) {
        if (startIndex > endIndex) {
            return new string[](0);
        }
        endIndex = endIndex > validatorCount - 1 ? validatorCount - 1 : endIndex;
        string[] memory stringAddresses = new string[](endIndex - startIndex + 1);
        uint256 currIdx = startIndex;
        uint256 strAddrIdx = 0;
        while (currIdx <= endIndex) {
            if (validatorRegistry[currIdx].validatorDepositStatus) {
                stringAddresses[strAddrIdx] = toString(abi.encodePacked(validatorRegistry[currIdx].pubKey));
                strAddrIdx++;
            }
            currIdx++;
        }
        return stringAddresses;
    }

    function getValidatorIndexByPublicKey(bytes calldata _publicKey) public view returns (uint256) {
        uint256 index = validatorPubKeyIndex[_publicKey];
        if (keccak256(_publicKey) == keccak256(validatorRegistry[index].pubKey)) return index;
        return type(uint256).max;
    }

    function toString(bytes memory data) private pure returns (string memory) {
        bytes memory alphabet = '0123456789abcdef';

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = '0';
        str[1] = 'x';
        for (uint256 i = 0; i < data.length; i++) {
            str[2 + i * 2] = alphabet[uint256(uint8(data[i] >> 4))];
            str[3 + i * 2] = alphabet[uint256(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }
}
