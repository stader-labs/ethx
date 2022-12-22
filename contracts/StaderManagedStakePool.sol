// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './interfaces/IDepositContract.sol';
import './interfaces/IStaderValidatorRegistry.sol';
import './interfaces/IStaderManagedStakePool.sol';

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
    IStaderValidatorRegistry public staderValidatorRegistry;

    bytes32 public constant STADER_PERMISSION_POOL_ADMIN = keccak256('STADER_PERMISSION_POOL_ADMIN');

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
        address _staderValidatorRegistry,
        address _staderPoolAdmin
    )
        external
        initializer
        checkZeroAddress(_ethValidatorDeposit)
        checkZeroAddress(_staderValidatorRegistry)
        checkZeroAddress(_staderPoolAdmin)
    {
        __Pausable_init();
        __AccessControl_init_unchained();
        withdrawCredential = _withdrawCredential;
        ethValidatorDeposit = IDepositContract(_ethValidatorDeposit);
        staderValidatorRegistry = IStaderValidatorRegistry(_staderValidatorRegistry);
        _grantRole(STADER_PERMISSION_POOL_ADMIN, _staderPoolAdmin);
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
        address _nodeRewardAddress,
        string calldata _nodeName,
        uint256 _nodeFees
    ) external onlyRole(STADER_PERMISSION_POOL_ADMIN) {
        require(
            staderValidatorRegistry.getValidatorIndexByPublicKey(_validatorPubkey) == type(uint256).max,
            'validator already in use'
        );
        staderValidatorRegistry.addToValidatorRegistry(
            false,
            _validatorPubkey,
            _validatorSignature,
            _depositDataRoot,
            'staderPermissionedPool',
            _nodeName,
            _nodeRewardAddress,
            _nodeFees,
            0
        );
    }

    /// @dev deposit 32 ETH in ethereum deposit contract
    function depositEthToDepositContract() external onlyRole(STADER_PERMISSION_POOL_ADMIN) {
        require(address(this).balance >= DEPOSIT_SIZE, 'not enough balance to deposit');
        uint256 validatorCount = staderValidatorRegistry.validatorCount();
        uint256 registeredValidatorCount = staderValidatorRegistry.registeredValidatorCount();
        require(registeredValidatorCount <= validatorCount, 'not enough validator to register');
        (, bytes memory pubKey, bytes memory signature, bytes32 depositDataRoot, , , , , ) = staderValidatorRegistry
            .validatorRegistry(registeredValidatorCount);

        //slither-disable-next-line arbitrary-send-eth
        ethValidatorDeposit.deposit{value: DEPOSIT_SIZE}(pubKey, withdrawCredential, signature, depositDataRoot);
        staderValidatorRegistry.incrementRegisteredValidatorCount();
        emit DepositToDepositContract(pubKey);
    }
}
