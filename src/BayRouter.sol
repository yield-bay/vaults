// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BayVault} from "./BayVault.sol";
import {WarpInV1} from "./warp/WarpIn.sol";
import {WarpBaseV1} from "./warp/base/WarpBase.sol";
import {ISolarERC20} from "./interface/solar/ISolarERC20.sol";
import {ISolarFactory} from "./interface/solar/ISolarFactory.sol";
import {ISolarPair} from "./interface/solar/ISolarPair.sol";
import {ISolarRouter02} from "./interface/solar/ISolarRouter02.sol";
import {IWETH} from "./interface/solar/IWETH.sol";
import {IYieldBayWarpIn} from "./interface/warp/IYieldBayWarpIn.sol";
import {IYieldBayWarpOut} from "./interface/warp/IYieldBayWarpOut.sol";
import "./lib/constants.sol";
import "./lib/errors.sol";

/// @title BayRouter
/// @author YieldBay team
/// @notice Routes any asset (solar ERC20 token/LP token/$NATIVE)
/// in/out of a bay vault for solarbeam farms.
/// User receives bayTokens for warping in an LP token, and
/// gets the LP token back on warping out.
/// @dev TODO: Enable warp out to any token (not just the LP token).
contract BayRouter is WarpBaseV1 {
    using SafeERC20 for IERC20;

    ISolarFactory public immutable solarFactory;
    ISolarRouter02 public immutable solarRouter;
    // solhint-disable-next-line var-name-mixedcase
    IWETH public immutable WNATIVE; // $WMOVR/$WGLMR

    constructor(
        ISolarRouter02 _router,
        ISolarFactory _factory,
        IWETH _WNATIVE // solhint-disable-line var-name-mixedcase
    ) {
        solarRouter = _router;
        solarFactory = _factory;
        WNATIVE = _WNATIVE;
    }

    /// @notice The warpIn function is used to buy LP tokens
    /// using ERC-20 tokens or the $NATIVE token, and deposit those LP tokens
    /// to the bayVault. The user may also deposit LP tokens directly if they
    /// already have it. bayVault shares are granted to the user corresponding
    /// to the amount of LP tokens deposited.
    /// @param vault address where the LP tokens should be deposited.
    /// @param fromToken address of the token to add liquidity with.
    /// @param path0 an array of addresses that represent the swap path for token0 in `vault.asset()`; Calculated off-chain.
    /// @param path1 an array of addresses that represent the swap path for token1 in `vault.asset()`; Calculated off-chain.
    /// @param amount amount of `fromToken` to add liquidity with.
    /// @param minLP minimum amount of LP tokens that should be received by adding liquidity; Calculated off-chain.
    /// @param converter address of the `IYieldBayWarpIn` contract.
    /// @return shares number of bayVault tokens bought.
    function warpIn(
        BayVault vault,
        IERC20 fromToken,
        address[] memory path0,
        address[] memory path1,
        uint256 amount,
        uint256 minLP,
        address converter
    ) external payable returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();

        _getTokens(fromToken, amount);

        ISolarPair solarPair = ISolarPair(address(vault.asset()));

        if (address(fromToken) == address(0)) {
            // Provided asset is $NATIVE.
            // IYieldBayWarpIn converts the provided asset to the desired LP token.
            uint256 lpBought = IYieldBayWarpIn(converter).warpIn{value: amount}(
                fromToken,
                solarPair,
                amount,
                minLP,
                path0,
                path1
            );

            solarPair.approve(address(vault), lpBought);
            shares = vault.deposit(lpBought, msg.sender);
        } else if (address(fromToken) == address(solarPair)) {
            // Provided asset is the LP token.
            // No need to use warp; simply deposit the tokens to the vault.
            uint256 balWarp = solarPair.balanceOf(address(this));
            if (amount > balWarp) revert InsufficientAmount();

            solarPair.approve(address(vault), amount);
            shares = vault.deposit(amount, msg.sender);
        } else {
            // Provided asset is an ERC-20 token.
            fromToken.approve(converter, amount);
            // IYieldBayWarpIn converts the provided asset to the desired LP token.
            uint256 lpBought = IYieldBayWarpIn(converter).warpIn(
                fromToken,
                solarPair,
                amount,
                minLP,
                path0,
                path1
            );

            solarPair.approve(address(vault), lpBought);
            shares = vault.deposit(lpBought, msg.sender);
        }
    }

    function warpOut(
        BayVault vault,
        IERC20 toToken,
        address[] memory path0,
        address[] memory path1,
        uint256 shares,
        address converter
    ) external returns (uint256 amountReceived) {
        if (shares == 0) revert ZeroAmount();

        ISolarPair solarPair = ISolarPair(address(vault.asset()));

        (IERC20 token0, IERC20 token1) = _fetchTokensFromPair(solarPair);

        if (
            !(address(toToken) == address(0) ||
                address(toToken) == address(vault.asset()) ||
                toToken == token0 ||
                toToken == token1)
        ) revert InvalidDestination(toToken);

        if (address(toToken) == address(solarPair)) {
            amountReceived = vault.redeem(shares, address(this), msg.sender);
            solarPair.transfer(msg.sender, amountReceived);
        } else {
            // console.log("othertok");
            uint256 lpAmountRedeemed = vault.redeem(
                shares,
                address(this),
                msg.sender
            );

            // console.log("lpardm", lpAmountRedeemed);
            // console.log("lpbalardm", solarPair.balanceOf(address(this)));
            solarPair.approve(converter, lpAmountRedeemed);
            // console.log("doneapprove");
            amountReceived = IYieldBayWarpOut(converter).warpOut(
                solarPair,
                toToken,
                lpAmountRedeemed,
                path0,
                path1
            );

            // console.log("ttbal", toToken.balanceOf(address(this)));

            if (address(toToken) == address(0)) {
                (bool success, ) = payable(msg.sender).call{
                    value: amountReceived
                }("");
                if (!success) revert SendValueFail();
            } else {
                toToken.safeTransfer(msg.sender, amountReceived);
            }
        }
    }

    // to receive $NATIVE
    receive() external payable {} // solhint-disable-line no-empty-blocks
}
