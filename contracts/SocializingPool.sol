// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

import './library/Address.sol';
import './interfaces/ISocializingPool.sol';
import './interfaces/IPoolSelector.sol';
import './interfaces/IStaderStakePoolManager.sol';
import './interfaces/IPermissionlessNodeRegistry.sol';
import './interfaces/IStaderOracle.sol';
import './interfaces/IPoolFactory.sol';

import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/cryptography/MerkleProofUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';

contract SocializingPool is ISocializingPool, Initializable, AccessControlUpgradeable, PausableUpgradeable {
    address public override poolHelper;
    address public poolFactory;
    address public override staderStakePoolManager;
    address public override staderTreasury;
    address public override oracle;
    address public override staderToken;
    uint256 public override totalELRewardsCollected;
    uint256 public constant CYCLE_DURATION = 28 days;
    uint256 public initialTimestamp;

    bytes32 public constant SOCIALIZE_POOL_OWNER = keccak256('SOCIALIZE_POOL_OWNER');
    bytes32 public constant REWARD_DISTRIBUTOR = keccak256('REWARD_DISTRIBUTOR');
    uint256 public constant TOTAL_STAKED_ETH = 32 ether;

    mapping(address => mapping(uint256 => bool)) public override claimedRewards;

    function initialize(
        address _adminOwner,
        address _staderStakePoolManager,
        address _staderTreasury,
        address _poolFactory,
        address _oracle,
        address _staderToken
    ) external initializer {
        Address.checkNonZeroAddress(_adminOwner);
        Address.checkNonZeroAddress(_staderStakePoolManager);
        Address.checkNonZeroAddress(_staderTreasury);
        Address.checkNonZeroAddress(_poolFactory);
        Address.checkNonZeroAddress(_oracle);
        Address.checkNonZeroAddress(_staderToken);

        __AccessControl_init_unchained();
        __Pausable_init();

        staderStakePoolManager = _staderStakePoolManager;
        staderTreasury = _staderTreasury;
        poolFactory = _poolFactory;
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

    function getRewardDetails() external view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
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
        bytes32[][] calldata _merkleProof,
        uint8 _poolId
    ) external override whenNotPaused {
        _claim(_index, msg.sender, _amountSD, _amountETH, _merkleProof);
        // Calculate totals
        uint256 totalAmountSD;
        uint256 totalAmountETH;
        for (uint256 i = 0; i < _index.length; i++) {
            totalAmountSD += _amountSD[i];
            totalAmountETH += _amountETH[i];
        }

        bool success;

        // distribute ETH rewards
        (uint256 userShare, uint256 operatorShare, uint256 protocolShare) = _calculateRewardShare(
            totalAmountETH,
            _poolId
        );
        IStaderStakePoolManager(staderStakePoolManager).receiveExecutionLayerRewards{value: userShare}();
        // slither-disable-next-line arbitrary-send-eth
        (success, ) = payable(staderTreasury).call{value: protocolShare}('');
        require(success, 'Protocol share transfer failed');
        // slither-disable-next-line arbitrary-send-eth
        if (operatorShare > 0) {
            (success, ) = payable(msg.sender).call{value: operatorShare}('');
            require(success, 'Operator share transfer failed');
        }

        // distribute SD rewards
        (userShare, operatorShare, protocolShare) = _calculateRewardShare(totalAmountSD, _poolId);

        IERC20Upgradeable(staderToken).transfer(staderStakePoolManager, userShare); // TODO: discuss if this is okay ?
        IERC20Upgradeable(staderToken).transfer(staderTreasury, protocolShare);
        if (operatorShare > 0) {
            IERC20Upgradeable(staderToken).transfer(msg.sender, operatorShare);
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

    function _calculateRewardShare(
        uint256 _totalRewards,
        uint8 _poolId
    ) internal view returns (uint256 _userShare, uint256 _operatorShare, uint256 _protocolShare) {
        uint256 collateralETH = getCollateralETH(_poolId);
        uint256 usersETH = TOTAL_STAKED_ETH - collateralETH;
        uint256 protocolFeePercent = getProtocolFeePercent(_poolId);
        uint256 operatorFeePercent = getOperatorFeePercent(_poolId);

        uint256 _userShareBeforeCommision = (usersETH * _totalRewards) / TOTAL_STAKED_ETH;
        _userShare = ((100 - protocolFeePercent - operatorFeePercent) * _userShareBeforeCommision) / 100;

        _operatorShare = (collateralETH * _totalRewards) / TOTAL_STAKED_ETH;
        _operatorShare += (operatorFeePercent * _userShareBeforeCommision) / 100;

        _protocolShare = (protocolFeePercent * _userShareBeforeCommision) / 100; // or _totalRewards - _userShare - _operatorShare
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

    function getProtocolFeePercent(uint8 _poolId) internal view returns (uint256) {
        return IPoolFactory(poolFactory).getProtocolFeePercent(_poolId);
    }

    function getOperatorFeePercent(uint8 _poolId) internal view returns (uint256) {
        return IPoolFactory(poolFactory).getOperatorFeePercent(_poolId);
    }

    function getCollateralETH(uint8 _poolId) private view returns (uint256) {
        return IPoolFactory(poolFactory).getCollateralETH(_poolId);
    }
}
