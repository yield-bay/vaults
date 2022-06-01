// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IComplexRewarder {
    function onBayReward(
        uint256 pid,
        address user,
        uint256 newLpAmount
    ) external;

    function pendingTokens(uint256 pid, address user)
        external
        view
        returns (uint256 pending);

    function rewardToken() external view returns (IERC20);

    function poolRewardsPerSec(uint256 pid) external view returns (uint256);
}
