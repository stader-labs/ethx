// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './interfaces/IStaderValidatorRegistry.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderValidatorRegistry is IStaderValidatorRegistry, Initializable, AccessControlUpgradeable {
    uint256 public override validatorCount;
    uint256 public override registeredValidatorCount;
    uint256 public constant override collateralETH = 4 ether;

    bytes32 public constant override STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');
    bytes32 public constant override STADER_SLASHING_MANAGER = keccak256('STADER_SLASHING_MANAGER');

    struct Validator {
        bool validatorDepositStatus; // state of validator
        bool isWithdrawal; //status of validator readiness to withdraw
        bytes pubKey; //public Key of the validator
        bytes signature; //signature for deposit to Ethereum Deposit contract
        bytes32 depositDataRoot; //deposit data root for deposit to Ethereum Deposit contract
        bytes32 staderPoolType; // validator pool type
        uint256 operatorId; // stader network assigned Id
        uint256 bondEth; // amount of bond eth in gwei
        uint256 penaltyCount; // penalty for MEV theft or any other wrong doing
    }
    mapping(uint256 => Validator) public override validatorRegistry;
    mapping(bytes => uint256) public override validatorPubKeyIndex;

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     * @param _validatorRegistryAdmin admin operator for operator registry
     */
    function initialize(address _validatorRegistryAdmin)
        external
        checkZeroAddress(_validatorRegistryAdmin)
        initializer
    {
        __AccessControl_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @dev add a validator to the registry
     * @param _pubKey public Key of the validator
     * @param _signature signature for deposit to Ethereum Deposit contract
     * @param _depositDataRoot deposit data root for deposit to Ethereum Deposit contract
     * @param _staderPoolType stader network pool type
     * @param _operatorId stader network assigned operator ID
     * @param _bondEth amount of bond eth in gwei
     */
    function addToValidatorRegistry(
        bytes memory _pubKey,
        bytes memory _signature,
        bytes32 _depositDataRoot,
        bytes32 _staderPoolType,
        uint256 _operatorId,
        uint256 _bondEth
    ) external override onlyRole(STADER_NETWORK_POOL) {
        Validator storage _validatorRegistry = validatorRegistry[validatorCount];
        _validatorRegistry.validatorDepositStatus = false;
        _validatorRegistry.isWithdrawal = false;
        _validatorRegistry.pubKey = _pubKey;
        _validatorRegistry.signature = _signature;
        _validatorRegistry.depositDataRoot = _depositDataRoot;
        _validatorRegistry.staderPoolType = _staderPoolType;
        _validatorRegistry.operatorId = _operatorId;
        _validatorRegistry.bondEth = _bondEth;
        _validatorRegistry.penaltyCount = 0;
        validatorPubKeyIndex[_pubKey] = validatorCount;
        validatorCount++;
        emit AddedToValidatorRegistry(_pubKey, _staderPoolType, validatorCount);
    }

    /**
     * @notice update the count of total registered validator on beacon chain
     * @dev only accept call from stader network pools
     * @param _pubKey public key of the validator
     */
    function incrementRegisteredValidatorCount(bytes memory _pubKey) external override onlyRole(STADER_NETWORK_POOL) {
        uint256 index = validatorPubKeyIndex[_pubKey];
        require(index != type(uint256).max, 'pubKey does not exist on registry');
        validatorRegistry[index].validatorDepositStatus = true;
        registeredValidatorCount++;
    }

    /**
     * @notice return the index of next permission less validator available for the deposit
     * @dev return uint256 max if no permission less validator is available
     * @param _poolType stader pool type of the validator
     * @param _inputOperatorId operatorID of a permissionLess operator
     */
    function getValidatorIndexForOperatorId(bytes32 _poolType, uint256 _inputOperatorId)
        external
        view
        override
        returns (uint256)
    {
        uint256 index = 0;
        while (index < validatorCount) {
            if (
                //slither-disable-next-line boolean-equal
                validatorRegistry[index].validatorDepositStatus == false &&
                validatorRegistry[index].staderPoolType == _poolType &&
                validatorRegistry[index].operatorId == _inputOperatorId
            ) {
                return index;
            }
            index++;
        }
        return type(uint256).max;
    }

    function getPoRAddressListLength() external view override returns (uint256) {
        return validatorCount;
    }

    function getPoRAddressList(uint256 startIndex, uint256 endIndex) external view override returns (string[] memory) {
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

    /**
     * @notice fetch validator index in the registry based on public key
     * @dev return uint256 max if no index is not found
     * @param _publicKey public key of the validator
     */
    function getValidatorIndexByPublicKey(bytes calldata _publicKey) external view override returns (uint256) {
        uint256 index = validatorPubKeyIndex[_publicKey];
        if (keccak256(_publicKey) == keccak256(validatorRegistry[index].pubKey)) return index;
        return type(uint256).max;
    }

    /**
     * @notice update the value of bond eth in case of permission less pool validators
     * @dev only accept call from stader slashing manager contract
     * @param _pubKey public key of the validator
     */
    function handleWithdrawnValidators(bytes memory _pubKey) external override onlyRole(STADER_SLASHING_MANAGER) {
        uint256 index = validatorPubKeyIndex[_pubKey];
        require(index != type(uint256).max, 'pubKey does not exist on registry');
        _removeValidatorFromRegistry(_pubKey, index);
    }

    function increasePenaltyCount(uint256 validatorIndex) external override onlyRole(STADER_SLASHING_MANAGER) {
        validatorRegistry[validatorIndex].penaltyCount++;
    }

    function updateBondEth(uint256 validatorIndex, uint256 currentBondEth)
        external
        override
        onlyRole(STADER_SLASHING_MANAGER)
    {
        validatorRegistry[validatorIndex].bondEth = currentBondEth;
    }

    function markValidatorReadyForWithdrawal(uint256 validatorIndex)
        external
        override
        onlyRole(STADER_SLASHING_MANAGER)
    {
        validatorRegistry[validatorIndex].isWithdrawal = true;
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

    function _removeValidatorFromRegistry(bytes memory _pubKey, uint256 _index) internal {
        delete (validatorRegistry[_index]);
        delete (validatorPubKeyIndex[_pubKey]);
        validatorCount--;
        registeredValidatorCount--;
        emit RemovedValidatorFromRegistry(_pubKey);
    }
}
