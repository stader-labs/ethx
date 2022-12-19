// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import './interfaces/IETHxVaultWithdrawer.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/access/AccessControl.sol';
import '@openzeppelin/contracts/security/Pausable.sol';

/**
 * @title ethXVault Contract
 * @author Stader Labs
 * @notice The ERC20 contract for the ethX token and Vault
 */
abstract contract ETHxVault is ERC20, ERC20Burnable, ERC4626, AccessControl, Pausable {
    using SafeMath for uint256;

    bytes32 public constant MINTER_ROLE = keccak256('MINTER_ROLE');
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');
    bytes32 public constant VAULT_ACCESS_ROLE = keccak256('VAULT_ACCESS_ROLE');

    mapping(address => uint256) contractEthBalances;

    event DepositedEthToVault(address indexed by, uint256 amount, uint256 time);
    event WithdrawnEthFromVault(address indexed by, uint256 amount, uint256 time);

    constructor() ERC20('ETHX', 'ETHX') {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        ERC4626(address(this));
    }

    /**
     * @notice Mints ethX when called by an authorized caller
     * @param to the account to mint to
     * @param amount the amount of ethX to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        _mint(to, amount);
    }

    /**
     * @notice Burns ethX when called by an authorized caller
     * @param account the account to burn from
     * @param amount the amount of ethX to burn
     */
    function burnFrom(address account, uint256 amount) public override onlyRole(MINTER_ROLE) whenNotPaused {
        _burn(account, amount);
    }

    function pause() public onlyRole(PAUSER_ROLE) whenNotPaused {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // Get a contract's ETH balance in the vault by address
    function balanceOfContract(address _contractName) external view returns (uint256) {
        return contractEthBalances[_contractName];
    }

    // Accept an ETH deposit from a pool manager
    // Require Vault Access Role to access this
    function depositEthToVault() external payable onlyRole(VAULT_ACCESS_ROLE) {
        require(msg.value > 0, 'No valid amount of ETH given to deposit');
        contractEthBalances[msg.sender] = contractEthBalances[msg.sender].add(msg.value);
        emit DepositedEthToVault(msg.sender, msg.value, block.timestamp);
    }

    // Withdraw an amount of ETH from vault
    // Require Vault Access Role to access this
    function withdrawEthFromVault(uint256 _amount) external onlyRole(VAULT_ACCESS_ROLE) {
        require(_amount > 0, 'No valid amount of ETH given to withdraw');
        require(contractEthBalances[msg.sender] >= _amount, 'Insufficient contract ETH balance');
        contractEthBalances[msg.sender] = contractEthBalances[msg.sender].sub(_amount);
        IETHxVaultWithdrawer withdrawer = IETHxVaultWithdrawer(msg.sender);
        withdrawer.receiveVaultWithdrawalETH{value: _amount}();
        emit WithdrawnEthFromVault(msg.sender, _amount, block.timestamp);
    }
}
