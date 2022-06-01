// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

abstract contract Log {
    // debugging
    event LogNamedUint(string name, uint256 value);
    event LogNamedAddress(string name, address addr);
}
