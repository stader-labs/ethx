// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import '../interfaces/IStaderConfig.sol';
import '../interfaces/INodeRegistry.sol';
import '../interfaces/IPoolFactory.sol';

library UtilLib {
    error ZeroAddress();
    error InvalidPubkeyLength();
    error CallerNotManager();
    error CallerNotOperator();
    error CallerNotStaderContract();
    error CallerNotWithdrawVault();

    /// @notice zero address check modifier
    function checkNonZeroAddress(address _address) internal pure {
        if (_address == address(0)) revert ZeroAddress();
    }

    //checks for Manager role in staderConfig
    function onlyManagerRole(address _addr, IStaderConfig _staderConfig) internal view {
        if (!_staderConfig.onlyManagerRole(_addr)) {
            revert CallerNotManager();
        }
    }

    function onlyOperatorRole(address _addr, IStaderConfig _staderConfig) internal view {
        if (!_staderConfig.onlyOperatorRole(_addr)) {
            revert CallerNotOperator();
        }
    }

    //checks if caller is a stader contract address
    function onlyStaderContract(
        address _addr,
        IStaderConfig _staderConfig,
        bytes32 _contractName
    ) internal view {
        if (!_staderConfig.onlyStaderContract(_addr, _contractName)) {
            revert CallerNotStaderContract();
        }
    }

    function getPubkeyForValidSender(
        uint8 _poolId,
        uint256 _validatorId,
        address _addr,
        IStaderConfig _staderConfig
    ) internal view returns (bytes memory) {
        address nodeRegistry = IPoolFactory(_staderConfig.getPoolFactory()).getNodeRegistry(_poolId);
        (, bytes memory pubkey, , , address withdrawVaultAddress, , , ) = INodeRegistry(nodeRegistry).validatorRegistry(
            _validatorId
        );
        if (_addr != withdrawVaultAddress) {
            revert CallerNotWithdrawVault();
        }
        return pubkey;
    }

    function getOperatorForValidSender(
        uint8 _poolId,
        uint256 _validatorId,
        address _addr,
        IStaderConfig _staderConfig
    ) internal view returns (address) {
        address nodeRegistry = IPoolFactory(_staderConfig.getPoolFactory()).getNodeRegistry(_poolId);
        (, , , , address withdrawVaultAddress, uint256 operatorId, , ) = INodeRegistry(nodeRegistry).validatorRegistry(
            _validatorId
        );
        if (_addr != withdrawVaultAddress) {
            revert CallerNotWithdrawVault();
        }
        (, , , , address operator) = INodeRegistry(nodeRegistry).operatorStructById(operatorId);
        return operator;
    }

    function onlyValidatorWithdrawVault(
        uint8 _poolId,
        uint256 _validatorId,
        address _addr,
        IStaderConfig _staderConfig
    ) internal view {
        address nodeRegistry = IPoolFactory(_staderConfig.getPoolFactory()).getNodeRegistry(_poolId);
        (, , , , address withdrawVaultAddress, , , ) = INodeRegistry(nodeRegistry).validatorRegistry(_validatorId);
        if (_addr != withdrawVaultAddress) {
            revert CallerNotWithdrawVault();
        }
    }

    function getNodeRecipientAddressByValidatorId(
        uint8 _poolId,
        uint256 _validatorId,
        IStaderConfig _staderConfig
    ) internal view returns (address payable) {
        address nodeRegistry = IPoolFactory(_staderConfig.getPoolFactory()).getNodeRegistry(_poolId);
        (, , , , , uint256 operatorId, , ) = INodeRegistry(nodeRegistry).validatorRegistry(_validatorId);
        return INodeRegistry(nodeRegistry).getOperatorRewardAddress(operatorId);
    }

    function getNodeRecipientAddressByOperatorId(
        uint8 _poolId,
        uint256 _operatorId,
        IStaderConfig _staderConfig
    ) internal view returns (address payable) {
        address nodeRegistry = IPoolFactory(_staderConfig.getPoolFactory()).getNodeRegistry(_poolId);
        return INodeRegistry(nodeRegistry).getOperatorRewardAddress(_operatorId);
    }

    function getNodeRecipientAddressByOperator(
        uint8 _poolId,
        address _operator,
        IStaderConfig _staderConfig
    ) internal view returns (address payable) {
        address nodeRegistry = IPoolFactory(_staderConfig.getPoolFactory()).getNodeRegistry(_poolId);
        uint256 operatorId = INodeRegistry(nodeRegistry).operatorIDByAddress(_operator);
        return INodeRegistry(nodeRegistry).getOperatorRewardAddress(operatorId);
    }
}
