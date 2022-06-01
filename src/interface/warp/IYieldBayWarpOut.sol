// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISolarPair} from "../solar/ISolarPair.sol";

interface IYieldBayWarpOut {
    function warpOut(
        ISolarPair fromLP,
        IERC20 to,
        uint256 lpAmount,
        address[] memory path0,
        address[] memory path1
    ) external returns (uint256 amountReceived);
}
