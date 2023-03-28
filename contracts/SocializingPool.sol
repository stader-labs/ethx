// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/IStaderConfig.sol';
import './interfaces/ISocializingPool.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';
import './interfaces/IStaderOracle.sol';
import './interfaces/IPoolFactory.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract SocializingPool is
    ISocializingPool,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    IStaderConfig public staderConfig;
    uint256 public override totalELRewardsCollected;
    uint256 public override totalOperatorETHRewardsRemaining;
    uint256 public override totalOperatorSDRewardsRemaining;
    uint256 public constant CYCLE_DURATION = 28 days;
    uint256 public initialTimestamp;

    bytes32 public constant STADER_ORACLE = keccak256('STADER_ORACLE');

    mapping(address => mapping(uint256 => bool)) public override claimedRewards;

    function initialize(address _staderConfig) external initializer {
        Address.checkNonZeroAddress(_staderConfig);

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        staderConfig = IStaderConfig(_staderConfig);
        initialTimestamp = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, staderConfig.getAdmin());
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev execution layer rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }

    function getRewardDetails()
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 currentIndex = IStaderOracle(staderConfig.getStaderOracle()).getCurrentRewardsIndex();
        uint256 currentStartTime = initialTimestamp + (currentIndex * CYCLE_DURATION);
        uint256 currentEndTime = currentStartTime + CYCLE_DURATION;
        uint256 nextIndex = currentIndex + 1;
        uint256 nextStartTime = currentEndTime + 1;
        uint256 nextEndTime = nextStartTime + CYCLE_DURATION;

        return (currentIndex, currentStartTime, currentEndTime, nextIndex, nextStartTime, nextEndTime);
    }

    function distributeUserRewards(uint256 _userETHRewards) external onlyRole(STADER_ORACLE) {
        (bool success, ) = payable(staderConfig.getStakePoolManager()).call{value: _userETHRewards}('');
        require(success, 'User ETH rewards transfer failed');
    }

    function distributeProtocolRewards(uint256 _protocolETHRewards) external onlyRole(STADER_ORACLE) {
        (bool success, ) = payable(staderConfig.getTreasury()).call{value: _protocolETHRewards}('');
        require(success, 'Protocol ETH rewards transfer failed');
    }

    function updateOperatorRewards(uint256 _operatorETHRewards, uint256 _operatorSDRewards)
        external
        onlyRole(STADER_ORACLE)
    {
        totalOperatorETHRewardsRemaining += _operatorETHRewards;
        totalOperatorSDRewardsRemaining += _operatorSDRewards;
    }

    function claim(
        uint256[] calldata _index,
        uint256[] calldata _amountSD,
        uint256[] calldata _amountETH,
        bytes32[][] calldata _merkleProof,
        address operatorRewardsAddr
    ) external override nonReentrant whenNotPaused {
        _claim(_index, msg.sender, _amountSD, _amountETH, _merkleProof);
        // Calculate totals
        uint256 totalAmountSD;
        uint256 totalAmountETH;
        for (uint256 i = 0; i < _index.length; i++) {
            totalAmountSD += _amountSD[i];
            totalAmountETH += _amountETH[i];
        }

        bool success;
        if (totalAmountETH > 0) {
            totalOperatorETHRewardsRemaining -= totalAmountETH;
            (success, ) = payable(operatorRewardsAddr).call{value: totalAmountETH}('');
            require(success, 'Operator ETH rewards transfer failed');
        }

        if (totalAmountSD > 0) {
            totalOperatorSDRewardsRemaining -= totalAmountSD;
            success = IERC20(staderConfig.getStaderToken()).transfer(operatorRewardsAddr, totalAmountSD);
            require(success, 'Operator SD rewards transfer failed');
        }
    }

    function _claim(
        uint256[] calldata _index,
        address _operator,
        uint256[] calldata _amountSD,
        uint256[] calldata _amountETH,
        bytes32[][] calldata _merkleProof
    ) internal {
        for (uint256 i = 0; i < _index.length; i++) {
            require(_amountSD[i] > 0 || _amountETH[i] > 0, 'Invalid amount');
            require(!claimedRewards[_operator][_index[i]], 'Already claimed');

            claimedRewards[_operator][_index[i]] = true;

            require(_verifyProof(_index[i], _operator, _amountSD[i], _amountETH[i], _merkleProof[i]), 'Invalid proof');
        }
    }

    // Verifies that the
    function _verifyProof(
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
}
