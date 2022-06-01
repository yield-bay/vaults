// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";

contract BaseTest is Test {
    uint256 public averageBlockTime = 20 seconds;

    function shift(uint256 _seconds) public {
        vm.warp(block.timestamp + _seconds);
        vm.roll(block.number + _seconds / averageBlockTime);
    }

    function updateAverageBlockTime(uint256 _averageBlockTime) public {
        averageBlockTime = _averageBlockTime;
    }
}
