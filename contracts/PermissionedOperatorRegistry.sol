// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';
import './abstract/OperatorRegistryBase.sol';

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PermissionedOperatorRegistry is OperatorRegistryBase, AccessControlUpgradeable, PausableUpgradeable {
  
    mapping(address => bool) public  isWhitelistedPermissionedNO;

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize(
        address _adminOwner,
        address _elRewardSocializePool
        )
        external
        initializer
    {
        Address.checkZeroAddress(_adminOwner);
        Address.checkZeroAddress(_elRewardSocializePool);
        __OperatorRegistryBase_init_(_elRewardSocializePool);
        __AccessControl_init_unchained();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    /**
     * @notice white list the permissioned node operators
     * @dev update the status of NOs in whitelist mapping, only owner can call
     * @param _nodeOperator wallet of node operator which will interact with contract
     */
    function whitelistPermissionedNOs(address[] calldata _nodeOperator)
        external
        onlyRole(OPERATOR_REGISTRY_OWNER)
    {
        for (uint256 i = 0; i < _nodeOperator.length; i++) {
            if (_nodeOperator[i] == address(0)) revert ZeroAddress();
            isWhitelistedPermissionedNO[_nodeOperator[i]] = true;
        }
        emit OperatorWhitelisted(_nodeOperator.length);
    }

    /**
     * @notice onboard a permissioned node operator
     * @dev only whitelistOperator can call
     * @param _operatorName name of operator
     * @param _operatorRewardAddress eth1 address of operator to get rewards and withdrawals
     * @return mevFeeRecipientAddress fee recipient address
     */
    function onboardPermissionedNodeOperator(
        string calldata _operatorName,
        address payable _operatorRewardAddress
    ) external  whenNotPaused returns (address mevFeeRecipientAddress) {
        Address.checkZeroAddress(_operatorRewardAddress);
        if (!isWhitelistedPermissionedNO[msg.sender]) revert OperatorNotWhitelisted();
        if (operatorRegistry[msg.sender].operatorId != 0) revert OperatorAlreadyOnBoarded();
        mevFeeRecipientAddress = elRewardSocializePool;
        _onboardOperator(true, _operatorName, _operatorRewardAddress);
        return mevFeeRecipientAddress;
    }

    /**
     * @notice increase the queued validator count for a operator
     * @dev only accept call from stader network contract
     * @param _operatorId operator ID
     */
    function incrementInitializedValidatorsCount(uint256 _operatorId) external onlyRole(STADER_NETWORK_POOL) {
        _incrementInitializedValidatorsCount(_operatorId);
    }

    /**
     * @notice reduce the queued validator count for a operator
     * @dev only accept call from stader network contract
     * @param _operatorId operator ID
     */
    function reduceInitializedValidatorsCount(uint256 _operatorId) external onlyRole(STADER_NETWORK_POOL) {
        _reduceInitializedValidatorsCount(_operatorId);
    }

    /**
     * @notice increase the queued validator count for a operator
     * @dev only accept call from stader network contract
     * @param _operatorId operator ID
     */
    function incrementQueuedValidatorsCount(uint256 _operatorId) external onlyRole(STADER_NETWORK_POOL) {
        _incrementQueuedValidatorsCount(_operatorId);
    }

    /**
     * @notice reduce the queued validator count for a operator
     * @dev only accept call from stader network contract
     * @param _operatorId operator ID
     */
    function reduceQueuedValidatorsCount(uint256 _operatorId) external onlyRole(STADER_NETWORK_POOL) {
        _reduceQueuedValidatorsCount(_operatorId);
    }

    /**
     * @notice increase the active validator count for a operator
     * @dev only accept call from stader network pools
     * @param _operatorId operator ID
     */
    function incrementActiveValidatorsCount(uint256 _operatorId) external onlyRole(STADER_NETWORK_POOL) {
        _incrementActiveValidatorsCount(_operatorId);
    }

    /**
     * @notice reduce the active validator count for a operator
     * @dev only accept call from stader network pools
     * @param _operatorId operator ID
     */
    function reduceActiveValidatorsCount(uint256 _operatorId) external onlyRole(STADER_NETWORK_POOL) {
        _reduceActiveValidatorsCount(_operatorId);
    }

    /**
     * @notice reduce the validator count from registry when a validator is withdrawn
     * @dev accept call, only from slashing manager contract
     * @param _operatorId operator ID
     */
    function incrementWithdrawValidatorsCount(uint256 _operatorId) external onlyRole(STADER_SLASHING_MANAGER) {
        _incrementWithdrawValidatorsCount(_operatorId);
    }

    /**
     * @dev Triggers stopped state.
     * should not be paused
     */
    function pause() external onlyRole(OPERATOR_REGISTRY_OWNER){
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * should not be paused
     */
    function unpause() external onlyRole(OPERATOR_REGISTRY_OWNER){
        _unpause();
    }
}
