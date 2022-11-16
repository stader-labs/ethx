// File: contracts/TimelockOwner.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract TimeLockOwner is Initializable {
    ///@notice time in secs for withholding ownership transfer
    uint256 public lockedPeriod;

    ///@dev timestamp of change owner request, owner can be changed after waiting for lockedPeriod
    uint256 public timestamp;

    /// @notice address of multisig admin account which act as the owner for Stader's Ethereum Staking DAO operations
    address public timeLockOwner;

    ///@notice address of new multisig admin account which will act as the new owner for Stader's
    /// Ethereum Staking DAO operations after lockedPeriod if change owner proposal not cancelled in the meantime
    address public timeLockOwnerCandidate;

    /// @notice event emitted when owner is updated
    event timeLockOwnerUpdated(address indexed newTimeLockOwner);

    /// @notice event emitted when new TimeLockOwner is proposed
    event timeLockOwnerProposed(address indexed proposedTimeLockOwner);

    /// @notice event emitted when new TimeLockOwner proposal cancelled
    event canceledTimeLockOwnerProposal(address indexed from);

    /// @notice Check for zero address
    /// @dev Modifier
    /// @param _address the address to check
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), "Address cannot be zero");
        _;
    }
    /// @notice Check for TimeLockOwner
    /// @dev Modifier
    modifier checkTimeLockOwner() {
        require(
            msg.sender == timeLockOwner,
            "Err NOT authorized for DAO operation"
        );
        _;
    }

    /// @notice initialize the setup parameters
    /// @param _timeLockOwner the address of owner/admin for carrying out the Doa operations
    function initializeTimeLockOwner(address _timeLockOwner)
        internal
        onlyInitializing
    {
        timeLockOwner = _timeLockOwner;
        lockedPeriod = 7200;
        timestamp = type(uint256).max;
        emit timeLockOwnerUpdated(_timeLockOwner);
    }

    /**
     * @dev Proposes a new TimelockOwner. Can only be called by the current timelockOwner
     */
    function proposeTimeLockOwner(address _timeLockOwnerCandidate)
        external
        checkZeroAddress(_timeLockOwnerCandidate)
        checkTimeLockOwner
    {
        timestamp = block.timestamp;
        timeLockOwnerCandidate = _timeLockOwnerCandidate;
        emit timeLockOwnerProposed(_timeLockOwnerCandidate);
    }

    /**
     * @notice Assigns the ownership of the contract to timeLockOwnerCandidate. Can only be called by the timeLockOwner.
     * @dev new time lock owner can be set after waiting for lockedPeriod
     */
    function acceptTimeLockOwnership() external checkTimeLockOwner {
        require(timestamp != (type(uint256).max), "No proposal active");
        require(
            timestamp + lockedPeriod >= block.timestamp,
            "Locking period not expired"
        );
        timeLockOwner = timeLockOwnerCandidate;
        emit timeLockOwnerUpdated(timeLockOwner);
    }

    /**
     * @dev Cancels the new time lock owner proposal.
     * Can only be called by the timeLockOwnerCandidate or timeLockOwner
     */
    function cancelTimeLockOwnerProposal() external {
        require(
            timeLockOwnerCandidate == msg.sender || timeLockOwner == msg.sender,
            "NOT authorized to cancel proposal"
        );
        timeLockOwnerCandidate = address(0);
        timestamp = type(uint256).max;
        emit canceledTimeLockOwnerProposal(msg.sender);
    }

    /**********************
     * Setter functions   *
     **********************/

    /// @notice Set the locking period for the transfer of timeLock ownership
    /// @param _lockedPeriod time in secs for withholding timeLock ownership transfer
    function setLockedPeriod(uint256 _lockedPeriod)
        external
        checkTimeLockOwner
    {
        lockedPeriod = _lockedPeriod;
    }
}
