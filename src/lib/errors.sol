// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./types.sol";

// BayRouter/warp
error ZeroAmount();
error HighSlippage();
error InvalidDestination(IERC20 destination);
error InsufficientAmount();
error InvalidToken(IERC20 token);
error SendValueFail();

// BayStrategy
error OnlyStrategist();
error OnlyVault();
error InvalidFee(FeeType feeType, uint256 fee);
error AddressNotUpdated(address addr, string message);
error ValueNotUpdated(uint256 value, string message);

// BayVault
error StrategyNotEnabled();
error InvalidDepositToken();
error AlreadyInitialized();
error NotInitialized();
error DuplicateStrategy();

// SolarStrategy
error InsufficientBalance();
error InsufficientAllowance();
error InvalidRoute(string message);
error SlippageOutOfBounds(uint256 value);

error InvalidVault(address vault);
