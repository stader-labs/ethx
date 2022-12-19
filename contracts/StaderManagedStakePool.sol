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

    /// @dev deposit 32 ETH in ethereum deposit contract
    function depositEthToDepositContract(
        bytes calldata pubKey,
        bytes calldata withdrawalCredentials,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external onlyRole(STADER_PERMISSION_POOL_ADMIN) {
        require(address(this).balance >= DEPOSIT_SIZE, 'not enough balance to deposit');

        //slither-disable-next-line arbitrary-send-eth
        ethValidatorDeposit.deposit{value: DEPOSIT_SIZE}(pubKey, withdrawalCredentials, signature, depositDataRoot);
        staderValidatorRegistry.addToValidatorRegistry(pubKey, withdrawalCredentials, signature, depositDataRoot);
        emit DepositToDepositContract(pubKey);
    }
}
