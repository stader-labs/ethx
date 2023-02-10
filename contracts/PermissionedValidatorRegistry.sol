// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './library/Address.sol';
import './abstract/ValidatorRegistryBase.sol';

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract PermissionedValidatorRegistry is ValidatorRegistryBase, AccessControlUpgradeable, PausableUpgradeable {

    /**
     * @dev Stader Staking Pool validator registry is initialized with following variables
     */
    function initialize(address _adminOwner, address _rewardFactory, address _operatorRegistry)
        external
        initializer
    {
        Address.checkZeroAddress(_adminOwner);
        Address.checkZeroAddress(_rewardFactory);
        Address.checkZeroAddress(_operatorRegistry);
        __ValidatorRegistryBase_init_(_rewardFactory,_operatorRegistry);
        __AccessControl_init_unchained();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);
    }

    function addValidatorKeys(
        bytes calldata _validatorPubKey,
        bytes calldata _validatorSignature,
        bytes32 _depositDataRoot
    ) external payable  {
        if (staderOperatorRegistry.isWhitelistedPermissionedNO(msg.sender)) revert OperatorNotWhitelisted();
        (, , , uint256 operatorId, , , , ) = staderOperatorRegistry.operatorRegistry(msg.sender);
        //TODO call SDlocker to check enough SD
        if (operatorId == 0) revert OperatorNotOnBoarded(); //check if it should be other way round, like !=0 then proceed
        _addValidatorKey(_validatorPubKey, _validatorSignature, 2, _depositDataRoot, operatorId);
    }

    function updatePoolHelper(address _staderPoolHelper)
        external
        onlyRole(STADER_NETWORK_POOL)
    {
        Address.checkZeroAddress(_staderPoolHelper);
        _updatePoolHelper(_staderPoolHelper);
    }

    /**
     * @dev Triggers stopped state.
     * should not be paused
     */
    function pause() external onlyRole(VALIDATOR_REGISTRY_ADMIN){
        _pause();
    }

    /**
     * @dev Returns to normal state.
     * should not be paused
     */
    function unpause() external onlyRole(VALIDATOR_REGISTRY_ADMIN){
        _unpause();
    }


}
