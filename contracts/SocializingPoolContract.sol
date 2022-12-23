// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/ISocializingPoolContract.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';

contract SocializingPoolContract is ISocializingPoolContract, Initializable, AccessControlUpgradeable {
    IStaderStakePoolManager public staderStakePoolManager;

    bytes32 public constant ADMIN_ROLE = keccak256('ADMIN_ROLE');

    /// @notice zero address check modifier
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), 'Address cannot be zero');
        _;
    }

    function initialize(address _staderStakePoolManager, address _elRewardContractOwner)
        external
        initializer
        checkZeroAddress(_staderStakePoolManager)
        checkZeroAddress(_elRewardContractOwner)
    {
        __AccessControl_init_unchained();
        staderStakePoolManager = IStaderStakePoolManager(_staderStakePoolManager);
        _grantRole(ADMIN_ROLE, _elRewardContractOwner);
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev execution layer rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.value);
    }

    /**
     * @notice Withdraw all accumulated rewards to Stader contract
     * @dev Can be called only by the Stader contract
     */
    function withdrawELRewards() external override returns (uint256 amount) {
        require(msg.sender == address(staderStakePoolManager), 'ONLY_STADER_CAN_WITHDRAW');

        uint256 balance = address(this).balance;
        if (balance > 0) {
            staderStakePoolManager.receiveExecutionLayerRewards{value: balance}();
        }
        return balance;
    }

    function updateStaderStakePoolManager(address _staderStakePoolManager)
        external
        onlyRole(ADMIN_ROLE)
        checkZeroAddress(_staderStakePoolManager)
    {
        staderStakePoolManager = IStaderStakePoolManager(_staderStakePoolManager);
    }
}
