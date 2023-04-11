// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './library/UtilLib.sol';

import './interfaces/IPoolFactory.sol';
import './interfaces/ISocializingPool.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';

import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract SocializingPool is ISocializingPool, Initializable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    IStaderConfig public override staderConfig;
    uint256 public override totalELRewardsCollected;
    uint256 public override totalOperatorETHRewardsRemaining;
    uint256 public override totalOperatorSDRewardsRemaining;
    uint256 public override initialBlock;

    bytes32 public constant STADER_ORACLE = keccak256('STADER_ORACLE');

    mapping(address => mapping(uint256 => bool)) public override claimedRewards;
    mapping(uint256 => bool) public handledRewards;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _staderConfig) external initializer {
        UtilLib.checkNonZeroAddress(_staderConfig);

        __Pausable_init();
        __ReentrancyGuard_init();

        staderConfig = IStaderConfig(_staderConfig);
        initialBlock = block.number;
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev execution layer rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function handleRewards(RewardsData calldata _rewardsData) external override nonReentrant onlyRole(STADER_ORACLE) {
        if (handledRewards[_rewardsData.index]) {
            revert RewardAlreadyHandled();
        }
        if (
            _rewardsData.operatorETHRewards + _rewardsData.userETHRewards + _rewardsData.protocolETHRewards >
            address(this).balance - totalOperatorETHRewardsRemaining
        ) {
            revert InsufficientETHRewards();
        }
        if (
            _rewardsData.operatorSDRewards >
            IERC20(staderConfig.getStaderToken()).balanceOf(address(this)) - totalOperatorSDRewardsRemaining
        ) {
            revert InsufficientSDRewards();
        }

        handledRewards[_rewardsData.index] = true;
        totalOperatorETHRewardsRemaining += _rewardsData.operatorETHRewards;
        totalOperatorSDRewardsRemaining += _rewardsData.operatorSDRewards;

        bool success;
        (success, ) = payable(staderConfig.getStakePoolManager()).call{value: _rewardsData.userETHRewards}('');
        if (!success) {
            revert ETHTransferFailed(staderConfig.getStakePoolManager(), _rewardsData.userETHRewards);
        }

        (success, ) = payable(staderConfig.getStaderTreasury()).call{value: _rewardsData.protocolETHRewards}('');
        if (!success) {
            revert ETHTransferFailed(staderConfig.getStaderTreasury(), _rewardsData.protocolETHRewards);
        }

        emit OperatorRewardsUpdated(
            _rewardsData.operatorETHRewards,
            totalOperatorETHRewardsRemaining,
            _rewardsData.operatorSDRewards,
            totalOperatorSDRewardsRemaining
        );

        emit UserETHRewardsTransferred(_rewardsData.userETHRewards);
        emit ProtocolETHRewardsTransferred(_rewardsData.protocolETHRewards);
    }

    function claim(
        uint256[] calldata _index,
        uint256[] calldata _amountSD,
        uint256[] calldata _amountETH,
        bytes32[][] calldata _merkleProof
    ) external override nonReentrant whenNotPaused {
        address operator = msg.sender;
        (uint256 totalAmountSD, uint256 totalAmountETH) = _claim(_index, operator, _amountSD, _amountETH, _merkleProof);

        uint8 poolId = IPoolFactory(staderConfig.getPoolFactory()).getOperatorPoolId(operator);
        address operatorRewardsAddr = getNodeRecipient(operator, poolId);

        bool success;
        if (totalAmountETH > 0) {
            totalOperatorETHRewardsRemaining -= totalAmountETH;
            (success, ) = payable(operatorRewardsAddr).call{value: totalAmountETH}('');
            if (!success) {
                revert ETHTransferFailed(operatorRewardsAddr, totalAmountETH);
            }
        }

        if (totalAmountSD > 0) {
            totalOperatorSDRewardsRemaining -= totalAmountSD;
            if (!IERC20(staderConfig.getStaderToken()).transfer(operatorRewardsAddr, totalAmountSD)) {
                revert SDTransferFailed();
            }
        }

        emit OperatorRewardsClaimed(operatorRewardsAddr, totalAmountETH, totalAmountSD);
    }

    function _claim(
        uint256[] calldata _index,
        address _operator,
        uint256[] calldata _amountSD,
        uint256[] calldata _amountETH,
        bytes32[][] calldata _merkleProof
    ) internal returns (uint256 _totalAmountSD, uint256 _totalAmountETH) {
        for (uint256 i = 0; i < _index.length; i++) {
            if (_amountSD[i] == 0 && _amountETH[i] == 0) {
                revert InvalidAmount();
            }
            if (claimedRewards[_operator][_index[i]]) {
                revert RewardAlreadyClaimed(_operator, _index[i]);
            }

            _totalAmountSD += _amountSD[i];
            _totalAmountETH += _amountETH[i];
            claimedRewards[_operator][_index[i]] = true;

            if (!verifyProof(_index[i], _operator, _amountSD[i], _amountETH[i], _merkleProof[i])) {
                revert InvalidProof(_index[i], _operator);
            }
        }
    }

    function verifyProof(
        uint256 _index,
        address _operator,
        uint256 _amountSD,
        uint256 _amountETH,
        bytes32[] calldata _merkleProof
    ) internal view returns (bool) {
        bytes32 merkleRoot = IStaderOracle(staderConfig.getStaderOracle()).socializingRewardsMerkleRoot(_index);
        bytes32 node = keccak256(abi.encodePacked(_operator, _amountSD, _amountETH));
        return MerkleProofUpgradeable.verify(_merkleProof, merkleRoot, node);
    }

    // TODO sanjay move to NodeRegistry?
    function getNodeRecipient(address _operator, uint8 _poolId) internal view returns (address) {
        INodeRegistry nodeRegistry = INodeRegistry(
            IPoolFactory(staderConfig.getPoolFactory()).getNodeRegistry(_poolId)
        );
        uint256 operatorId = nodeRegistry.operatorIDByAddress(_operator);
        return nodeRegistry.getOperatorRewardAddress(operatorId);
    }

    // SETTERS
    function updateStaderConfig(address _staderConfig) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        UtilLib.checkNonZeroAddress(_staderConfig);
        staderConfig = IStaderConfig(_staderConfig);
        emit UpdatedStaderConfig(_staderConfig);
    }

    // GETTERS

    function getRewardDetails()
        external
        view
        override
        returns (
            uint256 currentIndex,
            uint256 currentStartBlock,
            uint256 currentEndBlock,
            uint256 nextIndex,
            uint256 nextStartBlock,
            uint256 nextEndBlock
        )
    {
        uint256 cycleDuration = staderConfig.getSocializingPoolCycleDuration();
        currentIndex = IStaderOracle(staderConfig.getStaderOracle()).getCurrentRewardsIndex();
        currentStartBlock = initialBlock + ((currentIndex - 1) * cycleDuration);
        currentEndBlock = currentStartBlock + cycleDuration - 1;
        nextIndex = currentIndex + 1;
        nextStartBlock = currentEndBlock + 1;
        nextEndBlock = nextStartBlock + cycleDuration - 1;
    }
}
