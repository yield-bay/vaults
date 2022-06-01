// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

interface ISolarERC20 is IERC20, IERC20Permit {
    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function mint(address to, uint256 amount) external;

    function PERMIT_TYPEHASH() external pure returns (bytes32);
}
