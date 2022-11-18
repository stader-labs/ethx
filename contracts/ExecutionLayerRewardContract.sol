// SPDX-License-Identifier: MIT

pragma solidity ^0.8.2;

import "./interfaces/IStaderStakePoolManager.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract ExecutionLayerRewardContract is Initializable, AccessControlUpgradeable{

    IStaderStakePoolManager public staderStakePoolManager;

    bytes32 public constant EL_REWARD_CONTRACT_ADMIN_ROLE = keccak256("EL_REWARD_CONTRACT_ADMIN_ROLE");

    event ETHReceived(uint256 amount);

    /// @notice zero address check modifier
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), "Address cannot be zero");
        _;
    }

    function initialize(
        address _staderStakePoolManager,
        address _elRewardContractOwner
    )
    external initializer
    checkZeroAddress(_staderStakePoolManager)
    checkZeroAddress(_elRewardContractOwner)
    {
        __AccessControl_init_unchained();
        staderStakePoolManager = IStaderStakePoolManager(_staderStakePoolManager);
        _grantRole(EL_REWARD_CONTRACT_ADMIN_ROLE,_elRewardContractOwner);
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
    function withdrawELRewards() external returns (uint256 amount) {
        require(msg.sender == address(staderStakePoolManager), "ONLY_STADER_CAN_WITHDRAW");

        uint256 balance = address(this).balance;
        if (balance > 0) {
            staderStakePoolManager.receiveExecutionLayerRewards{value: balance}();
        }
        return balance;
    }

    function updateStaderStakePoolManager(address _staderStakePoolManager) external onlyRole(EL_REWARD_CONTRACT_ADMIN_ROLE)
    checkZeroAddress(_staderStakePoolManager)
    {
        staderStakePoolManager = IStaderStakePoolManager(_staderStakePoolManager);
    }

}