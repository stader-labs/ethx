// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract StaderPermissionLessValidatorRegistry is Initializable, AccessControlUpgradeable {
    
    address public staderPermissionLessPool;
    uint256 public validatorCount;

    bytes32 public constant PERMISSION_LESS_POOL = keccak256('PERMISSION_LESS_POOL');
    bytes32 public constant PERMISSION_LESS_REGISTRY_ADMIN = keccak256('PERMISSION_LESS_REGISTRY_ADMIN');

    /// @notice event emits after adding a validator to validatorRegistry
    event AddedToPermissionLessValidatorRegistry(bytes publicKey, uint256 count);

    struct PermissionLessValidator {
        bool validatorDepositStatus; // state of validator
        bytes pubKey; //public Key of the validator
        bytes signature; //signature for deposit to Ethereum Deposit contract
        bytes32 depositDataRoot; //deposit data root for deposit to Ethereum Deposit contract
        address nodeRewardAddress; //Eth1 address of node for reward
        string nodeName; // name of the node Operator
        uint256 nodeFees; // fee percentage of node
        uint256 bondEth; // amount of bond eth in gwei
    }
    mapping(uint256 => PermissionLessValidator) public validatorRegistry;
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
        _grantRole(PERMISSION_LESS_REGISTRY_ADMIN, msg.sender);
    }

    /**
     * @notice set stader permission-less stake pool address
     * @param _staderPermissionLessPool address of staderManagedStakePool
     */
    function setStaderPermissionLessPoolAddress(address _staderPermissionLessPool)
        external
        checkZeroAddress(_staderPermissionLessPool)
        onlyRole(PERMISSION_LESS_REGISTRY_ADMIN)
    {
        if (hasRole(PERMISSION_LESS_POOL, staderPermissionLessPool))
            _revokeRole(PERMISSION_LESS_POOL, staderPermissionLessPool);
        staderPermissionLessPool = _staderPermissionLessPool;
        _grantRole(PERMISSION_LESS_POOL, staderPermissionLessPool);
    }

    /**
     * @dev add a permission-less validator to the registry
     * @param _validatorDepositStatus status of validator
     * @param _pubKey public Key of the validator
     * @param _signature signature for deposit to Ethereum Deposit contract
     * @param _depositDataRoot deposit data root for deposit to Ethereum Deposit contract
     * @param _nodeName node operator identity
     * @param _nodeRewardAddress eth1 wallet of node for reward
     * @param _nodeFees node operator fees
     * @param _bondEth amount of bond eth in gwei
     */
    function addToValidatorRegistry(
        bool _validatorDepositStatus,
        bytes calldata _pubKey,
        bytes calldata _signature,
        bytes32 _depositDataRoot,
        string calldata _nodeName,
        address _nodeRewardAddress,
        uint256 _nodeFees,
        uint256 _bondEth
    ) external onlyRole(PERMISSION_LESS_POOL) {
        PermissionLessValidator storage _validatorRegistry = validatorRegistry[validatorCount];
        _validatorRegistry.validatorDepositStatus = _validatorDepositStatus;
        _validatorRegistry.pubKey = _pubKey;
        _validatorRegistry.signature = _signature;
        _validatorRegistry.depositDataRoot = _depositDataRoot;
        _validatorRegistry.nodeRewardAddress = _nodeRewardAddress;
        _validatorRegistry.nodeName = _nodeName;
        _validatorRegistry.nodeFees = _nodeFees;
        _validatorRegistry.bondEth = _bondEth;
        validatorPubKeyIndex[_pubKey] = validatorCount;
        validatorCount++;
        emit AddedToPermissionLessValidatorRegistry(_pubKey, validatorCount);
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
