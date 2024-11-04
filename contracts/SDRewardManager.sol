pragma solidity 0.8.16;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IStaderConfig } from "./interfaces/IStaderConfig.sol";
import { ISocializingPool } from "./interfaces/ISocializingPool.sol";
import { UtilLib } from "./library/UtilLib.sol";

/**
 * @title SDRewardManager
 * @notice This contract is responsible to add SD rewards to the socializing pool
 */
contract SDRewardManager is Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct SDRewardEntry {
        uint256 cycleNumber;
        uint256 amount;
        bool approved;
    }

    ///@notice Address of the Stader Config contract
    IStaderConfig public staderConfig;

    ///@notice Cycle number of the last added entry
    uint256 public lastEntryCycleNumber;

    // Mapping of cycle numbers to reward entries
    mapping(uint256 => SDRewardEntry) public rewardEntries;

    // Event emitted when a new reward entry is created
    event NewRewardEntry(uint256 indexed cycleNumber, uint256 amount);

    // Event emitted when a reward entry is approved
    event RewardEntryApproved(uint256 indexed cycleNumber, uint256 amount);

    error AccessDenied(address account);
    error EntryNotFound(uint256 cycleNumber);
    error EntryAlreadyApproved(uint256 cycleNumber);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract with a Stader configuration address
     * @param _staderConfig Address of the StaderConfig contract
     */
    function initialize(address _staderConfig) external initializer {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
    }

    /**
     * @notice Adds a new reward entry for the current cycle (fetched from socializing pool)
     * @param _amount The amount of SD to be rewarded
     */
    function addRewardEntry(uint256 _amount) external {
        if (!staderConfig.onlySDRewardEntryRole(msg.sender)) {
            revert AccessDenied(msg.sender);
        }
        uint256 cycleNumber = getCurrentCycleNumber();
        SDRewardEntry memory rewardEntry = rewardEntries[cycleNumber];

        if (rewardEntry.approved) {
            revert EntryAlreadyApproved(cycleNumber);
        }

        rewardEntry.cycleNumber = cycleNumber;
        rewardEntry.amount = _amount;
        lastEntryCycleNumber = cycleNumber;
        rewardEntries[cycleNumber] = rewardEntry;

        emit NewRewardEntry(cycleNumber, _amount);
    }

    /**
     * @notice Approves a reward entry for the current cycle (fetched from socializing pool) and transfers the reward amount.
     */
    function approveEntry() external {
        if (!staderConfig.onlySDRewardApproverRole(msg.sender)) {
            revert AccessDenied(msg.sender);
        }

        uint256 cycleNumber = getCurrentCycleNumber();

        SDRewardEntry storage rewardEntry = rewardEntries[cycleNumber];

        if (rewardEntry.cycleNumber == 0) {
            revert EntryNotFound(cycleNumber);
        }

        if (rewardEntry.approved) {
            revert EntryAlreadyApproved(cycleNumber);
        }

        rewardEntry.approved = true;

        if (rewardEntry.amount > 0) {
            IERC20Upgradeable(staderConfig.getStaderToken()).safeTransferFrom(
                msg.sender,
                staderConfig.getPermissionlessSocializingPool(),
                rewardEntry.amount
            );
            emit RewardEntryApproved(cycleNumber, rewardEntry.amount);
        }
    }

    /**
     * @notice Returns the latest reward entry
     * @return The latest SDRewardEntry struct for the most recent cycle
     */
    function viewLatestEntry() external view returns (SDRewardEntry memory) {
        return rewardEntries[lastEntryCycleNumber];
    }

    /**
     * @notice Fetch the current cycle number from permissionless socializing pool
     * @return Current cycle number
     */
    function getCurrentCycleNumber() public view returns (uint256) {
        return ISocializingPool(staderConfig.getPermissionlessSocializingPool()).getCurrentRewardsIndex();
    }
}
