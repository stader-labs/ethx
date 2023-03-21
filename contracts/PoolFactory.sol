// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/IPoolFactory.sol';
import './interfaces/IStaderPoolBase.sol';
import './interfaces/INodeRegistry.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PoolFactory is IPoolFactory, Initializable, AccessControlUpgradeable {
    mapping(uint8 => Pool) public override pools;
    uint8 public override poolCount;

    function initialize() external initializer {
        __AccessControl_init_unchained();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Add a new pool.
     * @dev This function should only be called by the owner of the contract.
     * @param _poolName The name of the new pool.
     * @param _poolAddress The address of the new pool contract.
     */
    function addNewPool(string calldata _poolName, address _poolAddress)
        external
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(bytes(_poolName).length > 0, 'Pool name cannot be empty');
        Address.checkNonZeroAddress(_poolAddress);

        pools[poolCount + 1] = Pool({poolName: _poolName, poolAddress: _poolAddress});
        poolCount++;

        emit PoolAdded(_poolName, _poolAddress);
    }

    /**
     * @notice Update the address of a pool.
     * @dev This function should only be called by the owner of the contract.
     * @param _poolId The ID of the pool to update.
     * @param _newPoolAddress The updated address of the pool.
     */
    function updatePoolAddress(uint8 _poolId, address _newPoolAddress)
        external
        override
        validPoolId(_poolId)
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        Address.checkNonZeroAddress(_newPoolAddress);

        pools[_poolId].poolAddress = _newPoolAddress;

        emit PoolAddressUpdated(_poolId, _newPoolAddress);
    }

    /// @inheritdoc IPoolFactory
    function getProtocolFee(uint8 _poolId) external view override validPoolId(_poolId) returns (uint256) {
        return IStaderPoolBase(pools[_poolId].poolAddress).protocolFee();
    }

    /// @inheritdoc IPoolFactory
    function getOperatorFee(uint8 _poolId) external view override validPoolId(_poolId) returns (uint256) {
        return IStaderPoolBase(pools[_poolId].poolAddress).operatorFee();
    }

    /// @inheritdoc IPoolFactory
    function getTotalActiveValidatorCount() public view override returns (uint256) {
        uint256 totalActiveValidatorCount;
        for (uint8 i = 1; i <= poolCount; i++) {
            totalActiveValidatorCount += getActiveValidatorCountByPool(i);
        }

        return totalActiveValidatorCount;
    }

    /// @inheritdoc IPoolFactory
    function getQueuedValidatorCountByPool(uint8 _poolId)
        external
        view
        override
        validPoolId(_poolId)
        returns (uint256)
    {
        return IStaderPoolBase(pools[_poolId].poolAddress).getTotalQueuedValidatorCount();
    }

    /// @inheritdoc IPoolFactory
    function getActiveValidatorCountByPool(uint8 _poolId) public view override validPoolId(_poolId) returns (uint256) {
        return IStaderPoolBase(pools[_poolId].poolAddress).getTotalActiveValidatorCount();
    }

    /// @inheritdoc IPoolFactory
    // TODO sanjay implement this pagination at pool level
    function getAllActiveValidators(uint256 pageNumber, uint256 pageSize)
        public
        view
        override
        returns (Validator[] memory)
    {
        uint256 startIndex = (pageNumber - 1) * pageSize;
        uint256 endIndex = startIndex + pageSize - 1;
        Validator[] memory allValidators = new Validator[](pageSize);

        uint256 index;
        for (uint8 i = 1; i <= poolCount; i++) {
            Validator[] memory validators = IStaderPoolBase(pools[i].poolAddress).getAllActiveValidators();
            uint256 validatorsCount = validators.length;
            uint256 fromIndex = startIndex > index ? startIndex - index : 0;
            uint256 toIndex = endIndex < index + validatorsCount - 1 ? endIndex - index + 1 : validatorsCount;

            if (startIndex <= index + validatorsCount - 1 && endIndex >= index) {
                for (uint256 j = fromIndex; j < toIndex; j++) {
                    if (startIndex + j < allValidators.length) {
                        allValidators[startIndex + j] = validators[j];
                    } else {
                        break;
                    }
                }
            }

            index += validatorsCount;

            if (index > endIndex) {
                break;
            }
        }

        return allValidators;
    }

    /// @inheritdoc IPoolFactory
    function retrieveValidator(bytes calldata _pubkey) public view override returns (Validator memory) {
        for (uint8 i = 1; i <= poolCount; i++) {
            if (getValidatorByPool(i, _pubkey).pubkey.length == 0) continue;

            return getValidatorByPool(i, _pubkey);
        }
        Validator memory emptyValidator;

        return emptyValidator;
    }

    /// @inheritdoc IPoolFactory
    function getValidatorByPool(uint8 _poolId, bytes calldata _pubkey) public view override returns (Validator memory) {
        return IStaderPoolBase(pools[_poolId].poolAddress).getValidator(_pubkey);
    }

    /// @inheritdoc IPoolFactory
    function retrieveOperator(bytes calldata _pubkey) public view override returns (Operator memory) {
        for (uint8 i = 1; i <= poolCount; i++) {
            if (getValidatorByPool(i, _pubkey).pubkey.length == 0) continue;

            return getOperator(i, _pubkey);
        }

        Operator memory emptyOperator;
        return emptyOperator;
    }

    /// @inheritdoc IPoolFactory
    function getOperator(uint8 _poolId, bytes calldata _pubkey) public view override returns (Operator memory) {
        return IStaderPoolBase(pools[_poolId].poolAddress).getOperator(_pubkey);
    }

    /// @inheritdoc IPoolFactory
    function getSocializingPoolAddress(uint8 _poolId) public view override returns (address) {
        return IStaderPoolBase(pools[_poolId].poolAddress).getSocializingPoolAddress();
    }

    /// @inheritdoc IPoolFactory
    function getOperatorTotalNonTerminalKeys(
        uint8 _poolId,
        address _nodeOperator,
        uint256 _startIndex,
        uint256 _endIndex
    ) public view override returns (uint256) {
        return
            IStaderPoolBase(pools[_poolId].poolAddress).getOperatorTotalNonTerminalKeys(
                _nodeOperator,
                _startIndex,
                _endIndex
            );
    }

    function getCollateralETH(uint8 _poolId) external view override returns (uint256) {
        return IStaderPoolBase(pools[_poolId].poolAddress).getCollateralETH();
    }

    // return validator full deposit amount on beacon chain
    function getBeaconChainDepositSize() external pure override returns (uint256) {
        return 32 ether;
    }

    function isExistingPubkey(bytes calldata _pubkey) external view override returns (bool) {
        for (uint8 i = 1; i <= poolCount; i++) {
            if (IStaderPoolBase(pools[i].poolAddress).isExistingPubkey(_pubkey)) return true;
        }
        return false;
    }

    // Modifiers
    modifier validPoolId(uint8 _poolId) {
        require(_poolId > 0 && _poolId <= poolCount, 'Invalid pool ID');
        _;
    }
}
