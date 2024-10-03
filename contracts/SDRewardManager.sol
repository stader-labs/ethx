pragma solidity 0.8.16;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IStaderConfig } from "./interfaces/IStaderConfig.sol";
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

    IStaderConfig public staderConfig;

    uint256 public latestCycleNumber;

    // Mapping of cycle numbers to reward entries
    mapping(uint256 => SDRewardEntry) public rewardEntries;

    // Event emitted when a new reward entry is created
    event NewRewardEntry(uint256 indexed cycleNumber, uint256 amount);

    // Event emitted when a reward entry is approved
    event RewardEntryApproved(uint256 indexed cycleNumber, uint256 amount);

    error AccessDenied(address account);
    error EntryNotFound(uint256 cycleNumber);
    error EntryAlreadyRegistered(uint256 cycleNumber);
    error EntryAlreadyApproved(uint256 cycleNumber);
    error InvalidCycleNumber(uint256 cycleNumber);

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
     * @notice Adds a new reward entry for a specified cycle
     * @param _cycleNumber The cycle number for the reward entry
     * @param _amount The amount of SD to be rewarded
     */
    function addRewardEntry(uint256 _cycleNumber, uint256 _amount) external {
        if (!staderConfig.isAllowedToCall(msg.sender, "addRewardEntry(uint256,uint256)")) {
            revert AccessDenied(msg.sender);
        }

        SDRewardEntry memory rewardEntry = rewardEntries[_cycleNumber];

        if (_cycleNumber < latestCycleNumber) {
            revert EntryAlreadyRegistered(_cycleNumber);
        }

        if (_cycleNumber > latestCycleNumber + 1) {
            revert InvalidCycleNumber(_cycleNumber);
        }

        if (rewardEntry.approved) {
            revert EntryAlreadyApproved(_cycleNumber);
        }

        rewardEntry.cycleNumber = _cycleNumber;
        rewardEntry.amount = _amount;
        latestCycleNumber = _cycleNumber;
        rewardEntries[_cycleNumber] = rewardEntry;

        emit NewRewardEntry(_cycleNumber, _amount);
    }

    /**
     * @notice Approves a reward entry for a specified cycle and transfers the reward amount.
     * @param _cycleNumber The cycle number for the reward entry
     */
    function approveEntry(uint256 _cycleNumber) external {
        if (!staderConfig.isAllowedToCall(msg.sender, "approveEntry(uint256)")) {
            revert AccessDenied(msg.sender);
        }

        SDRewardEntry storage rewardEntry = rewardEntries[_cycleNumber];

        if (rewardEntry.cycleNumber == 0) {
            revert EntryNotFound(_cycleNumber);
        }

        if (rewardEntry.approved) {
            revert EntryAlreadyApproved(_cycleNumber);
        }

        rewardEntry.approved = true;
        if (rewardEntry.amount > 0) {
            IERC20Upgradeable(staderConfig.getStaderToken()).safeTransferFrom(
                msg.sender,
                staderConfig.getPermissionlessSocializingPool(),
                rewardEntry.amount
            );
            emit RewardEntryApproved(_cycleNumber, rewardEntry.amount);
        }
    }

    /**
     * @notice Returns the latest reward entry
     * @return The latest SDRewardEntry struct for the most recent cycle
     */
    function viewLatestEntry() external view returns (SDRewardEntry memory) {
        return rewardEntries[latestCycleNumber];
    }
}
