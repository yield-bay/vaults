// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISolarFactory} from "../../interface/solar/ISolarFactory.sol";
import {ISolarPair} from "../../interface/solar/ISolarPair.sol";
import {ISolarRouter02} from "../../interface/solar/ISolarRouter02.sol";
import {IWETH} from "../../interface/solar/IWETH.sol";

/// @title Base contract for WarpIn & WarpOut
/// @author Nightwing from Yieldbay
/// @notice Base layer for Warp contracts. Functionality to pause, un-pause, and common functions shared between WarpIn.sol & WarpOut.sol
contract WarpBaseV1 is Ownable {
    using SafeERC20 for IERC20;

    bool public paused = false;

    /// @notice Toggles the pause state. Only owner() can call.
    /// @dev If paused is true, sets it to false. If paused is false, sets it to true.
    function togglePause() external onlyOwner {
        paused = !paused;
    }

    /// @notice Finds the addresses of the two tokens present in a Solarbeam liquidity pool.
    /// @param pair address of the solarbeam liquidity pool.
    /// @return token0 address of the first token in the liquidity pool pair.
    /// @return token1 address of the second token in the liquidity pool pair.
    function _fetchTokensFromPair(ISolarPair pair)
        internal
        view
        returns (IERC20 token0, IERC20 token1)
    {
        require(address(pair) != address(0), "PAIR_NOT_EXIST");

        token0 = IERC20(pair.token0());
        token1 = IERC20(pair.token1());
    }

    /// @notice Transfers the intended tokens from the address to the contract.
    /// @dev Used by WarpIn to obtain the token that the address wants to warp-in.
    /// @dev Used by WarpOut to obtain the LP tokens that the address wants to warp-out.
    /// @param from address of the token to transfer to the contract.
    /// @param amount the amount of `from` tokens to transfer to the contract.
    function _getTokens(IERC20 from, uint256 amount) internal {
        // If fromToken is zero address, transfer $MOVR
        if (address(from) != address(0)) {
            from.safeTransferFrom(msg.sender, address(this), amount);
            return;
        }
        require(amount == msg.value, "MOVR_NEQ_AMOUNT");
    }

    /// @notice Sends $MOVR to an address.
    /// @param amount amount of $MOVR to send.
    /// @param receiver destination address; where the $MOVR needs to be sent.
    function _sendNATIVE(uint256 amount, address payable receiver) internal {
        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = receiver.call{value: amount}("");
        require(success, "SEND_VALUE_FAIL");
    }

    modifier notPaused() {
        require(!paused, "CONTRACT_PAUSED");
        _;
    }
}
