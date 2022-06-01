// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISolarPair} from "../solar/ISolarPair.sol";

interface IYieldBayWarpIn {
    function warpIn(
        IERC20 fromToken,
        ISolarPair toPool,
        uint256 amountToWarp,
        uint256 minimumLPBought,
        address[] memory path0,
        address[] memory path1
    ) external payable returns (uint256 lpBought);
}
