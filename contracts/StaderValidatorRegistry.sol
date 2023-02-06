// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './interfaces/IStaderValidatorRegistry.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderValidatorRegistry is IStaderValidatorRegistry, Initializable, AccessControlUpgradeable {
    uint256 public override validatorCount;
    uint256 public override registeredValidatorCount;
    uint256 public constant override collateralETH = 4 ether;
    uint256 public DEPOSIT_SIZE = 32 ether;

    bytes32 public constant override STADER_NETWORK_POOL = keccak256('STADER_NETWORK_POOL');
    bytes32 public constant override STADER_SLASHING_MANAGER = keccak256('STADER_SLASHING_MANAGER');

    struct Validator {
        bool validatorDepositStatus; // state of validator
        bool isWithdrawal; //status of validator readiness to withdraw
        bytes pubKey; //public Key of the validator
        bytes signature; //signature for deposit to Ethereum Deposit contract
        bytes withdrawalAddress; //eth1 withdrawal address for validator
        bytes32 depositDataRoot; //deposit data root for deposit to Ethereum Deposit contract
        bytes32 staderPoolType; // validator pool type
        uint256 operatorId; // stader network assigned Id
        uint256 bondEth; // amount of bond eth in gwei
        uint256 penaltyCount; // penalty for MEV theft or any other wrong doing
    }
    mapping(uint256 => Validator) public override validatorRegistry;
    mapping(bytes => uint256) public override validatorRegistryIndexByPubKey;

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize() external initializer {
        __AccessControl_init_unchained();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // TODO add validator keys adding function
    function addValidatorKeys() external {
        //     bytes calldata _validatorPubkey,
        //     bytes calldata _validatorSignature,
        //     bytes32 _depositDataRoot,
        //     bytes32 _withdrawVaultSalt,
        //     uint256 _operatorId
        // ) external payable onlyRole(PERMISSION_LESS_OPERATOR) {
        //     require(msg.value == 4 ether, 'invalid collateral');
        //     require(
        //         staderValidatorRegistry.getValidatorIndexByPublicKey(_validatorPubkey) == type(uint256).max,
        //         'validator already in use'
        //     );
        //     uint256 operatorIndex = staderOperatorRegistry.getOperatorIndexById(_operatorId);
        //     require(operatorIndex == type(uint256).max, 'operatorNotOnboarded');
        //     staderOperatorRegistry.incrementValidatorCount(_operatorId);
        //     address withdrawVault = rewardVaultFactory.deployWithdrawVault(_withdrawVaultSalt, payable(withdrawVaultOwner));
        //     bytes memory withdrawCredential = rewardVaultFactory.getValidatorWithdrawCredential(withdrawVault);
        //     _validateKeys(_validatorPubkey, withdrawCredential, _validatorSignature, _depositDataRoot);
        //     staderValidatorRegistry.addToValidatorRegistry(
        //         _validatorPubkey,
        //         _validatorSignature,
        //         withdrawCredential,
        //         _depositDataRoot,
        //         PERMISSION_LESS_POOL,
        //         _operatorId,
        //         msg.value
        //     );
        //     standByPermissionLessValidators++;
    }

    /**
     * @notice update the count of total registered validator on beacon chain
     * @dev only accept call from stader network pools
     * @param _pubKey public key of the validator
     */
    function incrementRegisteredValidatorCount(bytes memory _pubKey) external override onlyRole(STADER_NETWORK_POOL) {
        uint256 index = getValidatorIndexByPublicKey(_pubKey);
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
    function getValidatorIndexByPublicKey(bytes memory _publicKey) public view override returns (uint256) {
        uint256 index = validatorRegistryIndexByPubKey[_publicKey];
        if (keccak256(_publicKey) == keccak256(validatorRegistry[index].pubKey)) return index;
        return type(uint256).max;
    }

    /**
     * @notice update the value of bond eth in case of permission less pool validators
     * @dev only accept call from stader slashing manager contract
     * @param _pubKey public key of the validator
     */
    function handleWithdrawnValidators(bytes memory _pubKey) external override onlyRole(STADER_SLASHING_MANAGER) {
        uint256 index = getValidatorIndexByPublicKey(_pubKey);
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
        delete (validatorRegistryIndexByPubKey[_pubKey]);
        // validatorCount--;
        // registeredValidatorCount--;
        emit RemovedValidatorFromRegistry(_pubKey);
    }

    function _validateKeys(
        bytes calldata pubkey,
        bytes memory withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) public view {
        bytes32 pubkey_root = sha256(abi.encodePacked(pubkey, bytes16(0)));
        bytes32 signature_root = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(signature[:64])),
                sha256(abi.encodePacked(signature[64:], bytes32(0)))
            )
        );
        bytes32 node = sha256(
            abi.encodePacked(
                sha256(abi.encodePacked(pubkey_root, withdrawal_credentials)),
                sha256(abi.encodePacked(DEPOSIT_SIZE, bytes24(0), signature_root))
            )
        );

        // Verify computed and expected deposit data roots match
        require(
            node == deposit_data_root,
            'DepositContract: reconstructed DepositData does not match supplied deposit_data_root'
        );
    }
}
