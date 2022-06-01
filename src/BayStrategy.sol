// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {BayVault} from "./BayVault.sol";
import "./lib/types.sol";
import "./lib/errors.sol";

/// @author Jack Sparrow from YieldBay
/// @notice Base strategy contract for YieldBay Snowball Machine.
abstract contract BayStrategy is Ownable, Pausable {
    using SafeTransferLib for ERC20;
    using SafeERC20 for IERC20;

    /// @notice BayVault address
    BayVault public vault;

    /// @notice The underlying asset
    ERC20 public depositToken;

    /// @notice The strategy developer's address
    /// @dev strategist fees are sent here.
    address public strategist;

    uint256 public minTokensToHarvest;
    uint256 public maxTokensToDepositWithoutHarvest;

    uint256 public vaultFeeBps = 1000;
    uint256 public strategistFeeBps = 0;
    uint256 public harvestRewardBps = 0;

    uint256 public constant BPS_DIVISOR = 10000;
    uint256 internal constant MAX_UINT = type(uint256).max;

    // event Deposit(address indexed account, uint256 amount);
    // event Withdraw(address indexed account, uint256 amount);
    // event Harvest(uint256 newTotalDeposits, uint256 newTotalSupply);
    // event Recovered(address token, uint256 amount);
    event UpdateVaultFee(uint256 oldValue, uint256 newValue);
    event UpdateStrategistFee(uint256 oldValue, uint256 newValue);
    event UpdateHarvestReward(uint256 oldValue, uint256 newValue);
    event UpdateMinTokensToHarvest(uint256 oldValue, uint256 newValue);
    event UpdateMaxTokensToDepositWithoutHarvest(
        uint256 oldValue,
        uint256 newValue
    );
    event UpdateStrategist(address oldValue, address newValue);

    constructor(BayVault _vault) {
        vault = _vault;
    }

    /// @notice Only called by the strategist
    modifier onlyStrategist() {
        if (msg.sender != strategist) revert OnlyStrategist();
        _;
    }

    /// @notice Only called by the corresponding vault
    modifier onlyVault() {
        if (msg.sender != address(vault)) revert OnlyVault();
        _;
    }

    function _giveAllowances() internal virtual;

    function _removeAllowances() internal virtual;

    function retireStrat() external virtual;

    function panic() external virtual;

    function pause() public virtual;

    function unpause() external virtual;

    /// @notice Deposit and deploy deposits tokens to the strategy
    /// @dev Must mint receipt tokens to `msg.sender`
    /// @param amount deposit tokens
    function deposit(uint256 amount) external virtual;

    /// @notice Deposit and deploy deposits tokens to the strategy
    function depositAll() external virtual;

    /// @notice Redeem receipt tokens for deposit tokens
    /// @param amount receipt tokens
    function withdraw(uint256 amount) external virtual;

    /// @notice Withdraw all funds from the strategy.
    function withdrawAll() external virtual;

    /// @notice Harvest reward tokens into deposit tokens
    function harvest(address harvestRewardRecipient) external virtual;

    /// @notice Called before depositing funds to the strategy
    function beforeDeposit(address harvestRewardRecipient) internal virtual;

    function chargeFees(
        address harvestRewardRecipient,
        IERC20 reward,
        address[] memory rewardToNativeRoute
    ) internal virtual;

    function balance() public view virtual returns (uint256);

    /// @notice Update harvest min threshold
    /// @param newValue threshold
    function updateMinTokensToHarvest(uint256 newValue) public onlyOwner {
        emit UpdateMinTokensToHarvest(minTokensToHarvest, newValue);
        minTokensToHarvest = newValue;
    }

    /// @notice Update harvest max threshold before a deposit
    /// @param newValue threshold
    function updateMaxTokensToDepositWithoutHarvest(uint256 newValue)
        public
        onlyOwner
    {
        emit UpdateMaxTokensToDepositWithoutHarvest(
            maxTokensToDepositWithoutHarvest,
            newValue
        );
        maxTokensToDepositWithoutHarvest = newValue;
    }

    /// @notice Update strategist fee
    /// @param newValue fee in BPS
    function updateStrategistFee(uint256 newValue) public onlyOwner {
        if (newValue + vaultFeeBps + harvestRewardBps > BPS_DIVISOR)
            revert InvalidFee(FeeType.StrategistFee, newValue);
        emit UpdateStrategistFee(strategistFeeBps, newValue);
        strategistFeeBps = newValue;
    }

    /// @notice Update vault fee
    /// @param newValue fee in BPS
    function updateVaultFee(uint256 newValue) public onlyOwner {
        if (newValue + strategistFeeBps + harvestRewardBps > BPS_DIVISOR)
            revert InvalidFee(FeeType.VaultFee, newValue);
        emit UpdateVaultFee(vaultFeeBps, newValue);
        vaultFeeBps = newValue;
    }

    /// @notice Update harvest reward
    /// @param newValue fee in BPS
    function updateHarvestReward(uint256 newValue) public onlyOwner {
        if (newValue + vaultFeeBps + strategistFeeBps > BPS_DIVISOR)
            revert InvalidFee(FeeType.HarvestReward, newValue);
        emit UpdateHarvestReward(harvestRewardBps, newValue);
        harvestRewardBps = newValue;
    }

    /// @notice Update strategist
    /// @param newValue address
    function updateStrategist(address newValue) public onlyStrategist {
        if (strategist == newValue)
            revert AddressNotUpdated(
                strategist,
                "Use a new strategist address"
            );
        emit UpdateStrategist(strategist, newValue);
        strategist = newValue;
    }
}
