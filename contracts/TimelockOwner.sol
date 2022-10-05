// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract TimelockOwner is Initializable {
    ///@notice time in secs for withholding ownership transfer
    uint256 public lockedPeriod;

    ///@dev timestamp of change owner request, owner can be changed after waiting for lockedPeriod
    uint256 public timestamp;

    /// @notice address of multisig admin account which act as the owner for Stader's Ethereum Staking DAO operations
    address public timelockOwner;

    ///@notice address of new multisig admin account which will act as the new owner for Stader's
    /// Ethereum Staking DAO operations after lockedPeriod if change owner proposal not cancelled in the meantime
    address public timelockOwnerCandidate;

    /// @notice event emitted when owner is updated
    event TimelockOwnerUpdated(address indexed newTimelockOwner);

    /// @notice event emitted when new TimelockOwner is proposed
    event TimelockOwnerProposed(address indexed proposedTimelockOwner);

    /// @notice event emitted when new TimelockOwner proposal cancelled
    event canceledTimelockOwnerProposal(address indexed from);

    /// @notice Check for zero address
    /// @dev Modifier
    /// @param _address the address to check
    modifier checkZeroAddress(address _address) {
        require(_address != address(0), "Address cannot be zero");
        _;
    }
    /// @notice Check for TimelockOwner
    /// @dev Modifier
    modifier checkTimelockOwner() {
        require(msg.sender == timelockOwner,"Errr NOT authorized for DAO operation");
        _;
    }

    /// @notice initialize the setup parameters
    /// @param _timelockOwner the address of owner/admin for carrying out the Doa operations
    function initializeTimelockOwner(address _timelockOwner)
        internal
        onlyInitializing
    {
        timelockOwner = _timelockOwner;
        lockedPeriod = 7200;
        timestamp= type(uint256).max;
        emit TimelockOwnerUpdated(_timelockOwner);
    }

    /**
     * @dev Proposes a new TimelockOwner. Can only be called by the current timelockOwner
     */
    function proposeTimelockOwner(address _timelockOwnerCandidate)
        external
        checkZeroAddress(_timelockOwnerCandidate)
        checkTimelockOwner
    {
        timestamp = block.timestamp;
        timelockOwnerCandidate = _timelockOwnerCandidate;
        emit TimelockOwnerProposed(_timelockOwnerCandidate);
    }

    /**
     * @notice Assigns the ownership of the contract to timelockOwnerCandidate. Can only be called by the timelockOwner.
     * @dev new time lock owner can be set after waiting for lockedPeriod
     */
    function acceptTimelockOwnership()
        external
        checkTimelockOwner
    {
        require(timestamp!=type(uint256).max, "NO Valid Proposal for ownership");
        require(
            timestamp + lockedPeriod >= block.timestamp,
            "Locking period not expired"
        );
        timelockOwner = timelockOwnerCandidate;
        emit TimelockOwnerUpdated(timelockOwner);
    }

    /**
     * @dev Cancels the new time lock owner proposal.
     * Can only be called by the timelockOwnerCandidate or timelockOwner
     */
    function cancelTimelockOwnerProposal() external {
        require(timelockOwnerCandidate == msg.sender || timelockOwner == msg.sender, "NOT authorized to cancel proposal");
        timelockOwnerCandidate = address(0);
        timestamp = type(uint256).max;
        emit canceledTimelockOwnerProposal(msg.sender);
    }

    /**********************
     * Setter functions   *
     **********************/

    /// @notice Set the locking period for the transfer of timelock ownership
    /// @param _lockedPeriod time in secs for withholding timelock ownership transfer
    function setLockedPeriod(uint256 _lockedPeriod)
        external
        checkTimelockOwner
    {
        lockedPeriod = _lockedPeriod;
    }
}
