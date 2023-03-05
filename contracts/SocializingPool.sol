// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/ISocializingPool.sol';
import './interfaces/IPoolSelector.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';
import './interfaces/IStaderOracle.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';

contract SocializingPool is ISocializingPool, Initializable, AccessControlUpgradeable {
    address public override poolHelper;
    address public override staderStakePoolManager;
    address public override staderTreasury;
    address public override oracle;
    address public override staderToken;
    uint256 public override totalELRewardsCollected;
    uint256 public constant CYCLE_DURATION = 28 days;
    uint256 public initialTimestamp;

    bytes32 public constant SOCIALIZE_POOL_OWNER = keccak256('SOCIALIZE_POOL_OWNER');
    bytes32 public constant REWARD_DISTRIBUTOR = keccak256('REWARD_DISTRIBUTOR');

    mapping(address => mapping(uint256 => bool)) public override claimedRewards;

    function initialize(
        address _adminOwner,
        address _staderStakePoolManager,
        address _staderTreasury,
        address _oracle,
        address _staderToken
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_staderStakePoolManager);
        Address.checkNonZeroAddress(_staderTreasury);
        Address.checkNonZeroAddress(_oracle);
        Address.checkNonZeroAddress(_staderToken);

        __AccessControl_init_unchained();

        staderStakePoolManager = _staderStakePoolManager;
        staderTreasury = _staderTreasury;
        oracle = _oracle;
        staderToken = _staderToken;
        initialTimestamp = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, _adminOwner);

        emit UpdatedStaderPoolManager(_staderStakePoolManager);
        emit UpdatedStaderTreasury(_staderTreasury);
        emit UpdatedOracle(_oracle);
        emit UpdatedStaderToken(_staderToken);
    }

    /**
     * @notice Allows the contract to receive ETH
     * @dev execution layer rewards may be sent as plain ETH transfers
     */
    receive() external payable {
        emit ETHReceived(msg.value);
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
        uint256 currentIndex = IStaderOracle(oracle).socializingRewardsIndex();
        uint256 currentStartTime = initialTimestamp + (currentIndex * CYCLE_DURATION);
        uint256 currentEndTime = currentStartTime + CYCLE_DURATION;
        uint256 nextIndex = currentIndex + 1;
        uint256 nextStartTime = currentEndTime + 1;
        uint256 nextEndTime = nextStartTime + CYCLE_DURATION;

        return (currentIndex, currentStartTime, currentEndTime, nextIndex, nextStartTime, nextEndTime);
    }

    function claim(
        uint256[] calldata _index,
        uint256[] calldata _amountSD,
        uint256[] calldata _amountETH,
        bytes32[][] calldata _merkleProof
    ) external override {
        _claim(_index, msg.sender, _amountSD, _amountETH, _merkleProof);
        // Calculate totals
        uint256 totalAmountSD;
        uint256 totalAmountETH;
        for (uint256 i = 0; i < _index.length; i++) {
            totalAmountSD += _amountSD[i];
            totalAmountETH += _amountETH[i];
        }
        IERC20Upgradeable(staderToken).transfer(msg.sender, totalAmountSD);
        if (totalAmountETH > 0) {
            (bool result, ) = payable(msg.sender).call{value: totalAmountETH}('');
            require(result, 'Failed to claim ETH');
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
        bytes32 merkleRoot = IStaderOracle(oracle).socializingRewardsMerkleRoot(_index);
        bytes32 node = keccak256(abi.encodePacked(_operator, _amountSD, _amountETH));
        return MerkleProofUpgradeable.verify(_merkleProof, merkleRoot, node);
    }

    function updateOracle(address _oracle) external override onlyRole(SOCIALIZE_POOL_OWNER) {
        Address.checkNonZeroAddress(_oracle);
        oracle = _oracle;
        emit UpdatedOracle(_oracle);
    }

    function updatePoolSelector(address _poolSelector) external onlyRole(SOCIALIZE_POOL_OWNER) {
        Address.checkNonZeroAddress(_poolSelector);
        poolHelper = _poolSelector;
        emit UpdatedPoolSelector(_poolSelector);
    }

    function updateStaderToken(address _staderToken) external onlyRole(SOCIALIZE_POOL_OWNER) {
        Address.checkNonZeroAddress(_staderToken);
        staderToken = _staderToken;
        emit UpdatedStaderToken(_staderToken);
    }

    /**
     * @dev update stader pool manager address
     * @param _staderStakePoolManager staderPoolManager address
     */
    function updateStaderStakePoolManager(address _staderStakePoolManager) external onlyRole(SOCIALIZE_POOL_OWNER) {
        Address.checkNonZeroAddress(_staderStakePoolManager);
        staderStakePoolManager = _staderStakePoolManager;
        emit UpdatedStaderPoolManager(_staderStakePoolManager);
    }

    /**
     * @dev update stader treasury address
     * @param _staderTreasury staderTreasury address
     */
    function updateStaderTreasury(address _staderTreasury) external onlyRole(SOCIALIZE_POOL_OWNER) {
        Address.checkNonZeroAddress(_staderTreasury);
        staderTreasury = _staderTreasury;
        emit UpdatedStaderTreasury(staderTreasury);
    }
}
