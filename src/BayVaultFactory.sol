// SPDX-License-Identifier: AGPL-3.0-only
// Adapted from https://github.com/Rari-Capital/vaults/blob/113727d4f728533ef1c76f0a7ca67d947a95340c/src/VaultFactory.sol
pragma solidity ^0.8.13;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

import {BayVault} from "./BayVault.sol";

/// @title Bay Vault Factory
/// @author YieldBay team, adapted from Rari-Capital/vaults
/// @notice Factory which enables deploying a Vault for any ERC20 token.
contract BayVaultFactory is Ownable {
    using Bytes32AddressLib for address;
    using Bytes32AddressLib for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(ERC20 => BayVault) public vaultForUnderlyingToken;

    EnumerableSet.AddressSet private vaults;
    EnumerableSet.AddressSet private underlyingTokens;

    function vaultsCount() external view returns (uint256) {
        return vaults.length();
    }

    function vaultAt(uint256 index) external view returns (address) {
        return vaults.at(index);
    }

    function vaultsList() external view returns (address[] memory) {
        return vaults.values();
    }

    function underlyingTokensList() external view returns (address[] memory) {
        return underlyingTokens.values();
    }

    /*///////////////////////////////////////////////////////////////
                          VAULT DEPLOYMENT LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new Vault is deployed.
    /// @param vault The newly deployed Vault contract.
    /// @param underlying The underlying token the new Vault accepts.
    event VaultDeployed(BayVault indexed vault, ERC20 underlying);

    /// @notice Deploys a new Vault which supports a specific underlying token.
    /// @dev This will revert if a Vault that accepts the same underlying token has already been deployed.
    /// @param underlying The ERC20 token that the Vault should accept.
    /// @param underlyingName The name of the underlying ERC20 token.
    /// @param underlyingSymbol The symbol of the underlying ERC20 token.
    /// @param bayTreasury Address of the YieldBay treasury.
    /// @return vault The newly deployed Vault contract which accepts the provided underlying token.
    function deployVault(
        ERC20 underlying,
        string memory underlyingName,
        string memory underlyingSymbol,
        address bayTreasury
    ) external returns (BayVault vault) {
        // Use the CREATE2 opcode to deploy a new Vault contract.
        // This will revert if a Vault which accepts this underlying token has already
        // been deployed, as the salt would be the same and we can't deploy with it twice.
        vault = new BayVault{salt: address(underlying).fillLast12Bytes()}(
            underlying,
            underlyingName,
            underlyingSymbol,
            bayTreasury
        );

        vaults.add(address(vault));
        underlyingTokens.add(address(underlying));
        vaultForUnderlyingToken[underlying] = vault;

        emit VaultDeployed(vault, underlying);

        vault.transferOwnership(msg.sender);
    }

    /*///////////////////////////////////////////////////////////////
                            VAULT LOOKUP LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Computes a Vault's address from its accepted underlying token.
    /// @param underlying The ERC20 token that the Vault should accept.
    /// @return The address of a Vault which accepts the provided underlying token.
    /// @dev The Vault returned may not be deployed yet. Use isVaultDeployed to check.
    function getVaultFromUnderlying(
        ERC20 underlying,
        string memory underlyingName,
        string memory underlyingSymbol,
        address bayTreasury
    ) external view returns (BayVault) {
        return
            BayVault(
                payable(
                    keccak256(
                        abi.encodePacked(
                            // Prefix:
                            bytes1(0xFF),
                            // Creator:
                            address(this),
                            // Salt:
                            address(underlying).fillLast12Bytes(),
                            // Bytecode hash:
                            keccak256(
                                abi.encodePacked(
                                    // Deployment bytecode:
                                    type(BayVault).creationCode,
                                    // Constructor arguments:
                                    abi.encode(
                                        underlying,
                                        underlyingName,
                                        underlyingSymbol,
                                        bayTreasury
                                    )
                                )
                            )
                        )
                    ).fromLast20Bytes() // Convert the CREATE2 hash into an address.
                )
            );
    }

    /// @notice Returns if a Vault at an address has already been deployed.
    /// @param vault The address of a Vault which may not have been deployed yet.
    /// @return A boolean indicating whether the Vault has been deployed already.
    /// @dev This function is useful to check the return values of getVaultFromUnderlying,
    /// as it does not check that the Vault addresses it computes have been deployed yet.
    function isVaultDeployed(BayVault vault) external view returns (bool) {
        return address(vault).code.length > 0;
    }
}
