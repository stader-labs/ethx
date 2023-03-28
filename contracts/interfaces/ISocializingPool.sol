// SPDX-License-Identifier: MIT

pragma solidity ^0.8.16;

interface ISocializingPool {
    event ETHReceived(address indexed sender, uint256 amount);
    event UpdatedStaderValidatorRegistry(address staderValidatorRegistry);
    event UpdatedStaderOperatorRegistry(address staderOperatorRegistry);

    function distributeUserRewards(uint256 _userRewardsAmt) external;

    function distributeProtocolRewards(uint256 _protocolRewardsAmt) external;

    function updateOperatorRewards(uint256 _operatorETHRewards, uint256 _operatorSDRewards) external;

    function claimedRewards(address _user, uint256 _index) external view returns (bool);

    function totalELRewardsCollected() external view returns (uint256);

    function totalOperatorETHRewardsRemaining() external view returns (uint256);

    function totalOperatorSDRewardsRemaining() external view returns (uint256);

    function claim(
        uint256[] calldata _index,
        uint256[] calldata _amountSD,
        uint256[] calldata _amountETH,
        bytes32[][] calldata _merkleProof,
        address operatorRewardsAddr
    ) external;
}
