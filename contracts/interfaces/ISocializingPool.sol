// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface ISocializingPool {
    event ETHReceived(address indexed sender, uint256 amount);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);
    event UpdatedOracle(address oracleAddress);
    event UpdatedPoolSelector(address poolSelector);

    function poolSelector() external view returns (address);

    function oracle() external view returns (address);

    function claimedRewards(address _user, uint256 _index) external view returns (bool);

    function totalELRewardsCollected() external view returns (uint256);

    function updateOracle(address _oracle) external;

    function claim(
        uint256[] calldata _index,
        uint256[] calldata _amountSD,
        uint256[] calldata _amountETH,
        bytes32[][] calldata _merkleProof,
        uint8 _poolId
    ) external;
}
