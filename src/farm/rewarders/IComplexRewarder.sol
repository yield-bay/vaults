// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {BoringERC20} from "../libraries/BoringERC20.sol";
import {IBoringERC20} from "../libraries/IBoringERC20.sol";

interface IComplexRewarderYB {
    function onBayReward(
        uint256 pid,
        address user,
        uint256 newLpAmount
    ) external;

    function pendingTokens(uint256 pid, address user)
        external
        view
        returns (uint256 pending);

    function rewardToken() external view returns (IBoringERC20);

    function poolRewardsPerSec(uint256 pid) external view returns (uint256);
}
