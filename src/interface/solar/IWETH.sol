// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

/// The chain's native token,
/// i.e., $MOVR for moonriver/solarbeam
/// and $GLMR for moonbeam/solarflare)
interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}
