pragma solidity 0.8.16;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IStaderConfig } from "./interfaces/IStaderConfig.sol";
import { UtilLib } from "./library/UtilLib.sol";

contract SDRewardManager is Initializable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct SDRewardEntry {
        uint256 cycleNumber;
        uint256 amount; // in exact SD value, not in gwei or wei
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
    error EntryAlreadApproved(uint256 cycleNumber);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _staderConfig) external initializer {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
    }

    function addRewardEntry(uint256 _cycleNumber, uint256 _amount) external {
        if (!staderConfig.isAllowedToCall(msg.sender, "addRewardEntry(uint256,uint256)")) {
            revert AccessDenied(msg.sender);
        }

        if (_cycleNumber <= latestCycleNumber) {
            revert EntryAlreadyRegistered(_cycleNumber);
        }

        SDRewardEntry storage rewardEntry = rewardEntries[_cycleNumber];
        rewardEntry.cycleNumber = _cycleNumber;
        rewardEntry.amount = _amount;
        latestCycleNumber = _cycleNumber;

        emit NewRewardEntry(_cycleNumber, _amount);
    }

    function approveEntry(uint256 _cycleNumber, uint256 _amount) external {
        if (!staderConfig.isAllowedToCall(msg.sender, "approveEntry(uint256,uint256)")) {
            revert AccessDenied(msg.sender);
        }

        SDRewardEntry storage rewardEntry = rewardEntries[_cycleNumber];

        if (rewardEntry.cycleNumber == 0) {
            revert EntryNotFound(_cycleNumber);
        }

        if (rewardEntry.approved) {
            revert EntryAlreadApproved(_cycleNumber);
        }

        rewardEntry.approved = true;
        if (rewardEntry.amount > 0) {
            IERC20Upgradeable(staderConfig.getStaderToken()).safeTransferFrom(
                msg.sender,
                staderConfig.getPermissionlessSocializingPool(),
                _amount
            );
            emit RewardEntryApproved(_cycleNumber, _amount);
        }
    }

    function viewLatestEntry() external view returns (SDRewardEntry memory) {
        return rewardEntries[latestCycleNumber];
    }
}
