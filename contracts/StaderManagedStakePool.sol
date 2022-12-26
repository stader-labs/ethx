// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './interfaces/IDepositContract.sol';
import './interfaces/IStaderValidatorRegistry.sol';
import './interfaces/IStaderManagedStakePool.sol';
import './interfaces/IStaderOperatorRegistry.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';

contract StaderManagedStakePool is
    IStaderManagedStakePool,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable
{
    uint256 public constant DEPOSIT_SIZE = 32 ether;
    IDepositContract public ethValidatorDeposit;
    bytes public withdrawCredential;
    IStaderOperatorRegistry public staderOperatorRegistry;
    IStaderValidatorRegistry public staderValidatorRegistry;

    bytes32 public constant STADER_PERMISSION_POOL_ADMIN = keccak256('STADER_PERMISSION_POOL_ADMIN');
    bytes32 public constant STADER_POOL_MANAGER = keccak256('STADER_POOL_MANAGER');

    /// @notice zero address check modifier
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    /**
     * @dev Stader managed stake Pool is initialized with following variables
     */
    function initialize(
        address _ethValidatorDeposit,
        bytes calldata _withdrawCredential,
        address _staderOperatorRegistry,
        address _staderValidatorRegistry,
        address _staderPoolAdmin
    )
        external
        initializer
        checkZeroAddress(_ethValidatorDeposit)
        checkZeroAddress(_staderOperatorRegistry)
        checkZeroAddress(_staderValidatorRegistry)
        checkZeroAddress(_staderPoolAdmin)
    {
        __Pausable_init();
        __AccessControl_init_unchained();
        withdrawCredential = _withdrawCredential;
        ethValidatorDeposit = IDepositContract(_ethValidatorDeposit);
        staderOperatorRegistry = IStaderOperatorRegistry(_staderOperatorRegistry);
        staderValidatorRegistry = IStaderValidatorRegistry(_staderValidatorRegistry);
        _grantRole(STADER_PERMISSION_POOL_ADMIN, _staderPoolAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev stader pool manager send ETH to stader managed stake pool
     */
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }

    /**
     * @notice permission pool validator onboarding
     * @dev register the permission pool validators in stader validator registry
     *
     */
    function registerPermissionValidator(
        bytes calldata _validatorPubkey,
        bytes calldata _validatorSignature,
        bytes32 _depositDataRoot,
        address _operatorRewardAddress,
        string calldata _operatorName,
        uint256 _operatorId
    ) external onlyRole(STADER_PERMISSION_POOL_ADMIN) {
        require(
            staderValidatorRegistry.getValidatorIndexByPublicKey(_validatorPubkey) == type(uint256).max,
            'validator already in use'
        );
        uint256 operatorIndex = staderOperatorRegistry.getOperatorIndexById(_operatorId);
        if (operatorIndex == type(uint256).max) {
            staderOperatorRegistry.addToOperatorRegistry(_operatorRewardAddress, _operatorName, _operatorId, 1, 0, 0);
        } else {
            staderOperatorRegistry.incrementValidatorCount(_operatorId);
        }
        staderValidatorRegistry.addToValidatorRegistry(
            false,
            _validatorPubkey,
            _validatorSignature,
            _depositDataRoot,
            'staderPermissionedPool',
            _operatorId,
            0
        );
    }

    /// @dev deposit 32 ETH in ethereum deposit contract
    function depositEthToDepositContract() external payable onlyRole(STADER_POOL_MANAGER) {
        require(address(this).balance >= DEPOSIT_SIZE, 'not enough balance to deposit');
        uint256 validatorCount = staderValidatorRegistry.validatorCount();
        uint256 registeredValidatorCount = staderValidatorRegistry.registeredValidatorCount();
        require(registeredValidatorCount <= validatorCount, 'not enough validator to register');
        (
            ,
            bytes memory pubKey,
            bytes memory signature,
            bytes32 depositDataRoot,
            ,
            uint256 operatorId,

        ) = staderValidatorRegistry.validatorRegistry(registeredValidatorCount);

        //slither-disable-next-line arbitrary-send-eth
        ethValidatorDeposit.deposit{value: DEPOSIT_SIZE}(pubKey, withdrawCredential, signature, depositDataRoot);
        staderValidatorRegistry.incrementRegisteredValidatorCount();
        staderOperatorRegistry.incrementActiveValidatorCount(operatorId);
        emit DepositToDepositContract(pubKey);
    }
}
