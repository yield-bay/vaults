// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "./constants.sol";

import {ISolarPair} from "../interface/solar/ISolarPair.sol";
import {ISolarRouter02} from "../interface/solar/ISolarRouter02.sol";

library Utils {
    function calculateMinimumLP(
        ISolarPair solarPair,
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 slippage
    ) public view returns (uint256 minLP) {
        uint256 reserve0;
        uint256 reserve1;
        (reserve0, reserve1, ) = solarPair.getReserves();

        uint256 totalSupply = solarPair.totalSupply();

        uint256 value0 = (token0Amount * totalSupply) / (reserve0);
        uint256 value1 = (token1Amount * totalSupply) / (reserve1);

        minLP = value0 < (value1) ? value0 : value1;

        // `slippage` should be a number between 0 & 100.
        minLP = (minLP * (100 - slippage)) / (100);
    }

    function getAmountsOut(
        ISolarRouter02 solarRouter,
        uint256 amount,
        address[] memory path
    ) public view returns (uint256) {
        uint256[] memory amountsOut = solarRouter.getAmountsOut(
            amount,
            path,
            SOLAR_FEE
        );
        return amountsOut[path.length - 1];
    }
}
