// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

// import "@boringcrypto/boring-solidity/contracts/libraries/BoringERC20.sol";

interface IRewarder {
    function onBayReward(
        uint256 pid,
        address user,
        address recipient,
        uint256 rewardAmount,
        uint256 newLpAmount
    ) external;

    function pendingTokens(
        uint256 pid,
        address user,
        uint256 rewardAmount
    ) external view returns (IERC20[] memory, uint256[] memory);
}
