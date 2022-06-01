// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Pausable} from "openzeppelin/contracts/security/Pausable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {BayChef} from "./farm/BayChef.sol";
import {BayStrategy} from "./BayStrategy.sol";
import "./lib/errors.sol";

/// @title Bay Vault
/// @author Jack Sparrow from YieldBay
/// @notice Autocompounding yield aggregator (Snowball Machine).
contract BayVault is ERC4626, Ownable, Pausable {
    using SafeTransferLib for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Active strategy where deposits are sent by default
    BayStrategy public activeStrategy;

    /// @notice Treasury address where vault fees are sent
    address public bayTreasury;

    mapping(address => uint256) public strategyIdForStrategyAddress;
    mapping(address => uint256[]) public strategyIdsForDepositToken;

    EnumerableSet.AddressSet private strategies;

    event AddStrategy(uint256 id, address indexed strategy);

    /// @notice Emitted when the active strategy is updated.
    event SetActiveStrategy(address indexed strategy);

    /// @notice Emitted when the Vault is initialized.
    /// @param user The authorized user who triggered the initialization.
    /// @param strategy The strategy to use by default.
    event Initialized(address indexed user, address indexed strategy);

    /// @param _asset The underlying token the Vault accepts. (eg: DAI-USDC LP Token)
    /// @param _name Name of the underlying token. (eg: DAI-USDC LP)
    /// @param _symbol Symbol of the underlying token. (eg: DAI-USDC)
    /// @param _bayTreasury The YieldBay treasury address.
    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _bayTreasury
    )
        ERC4626(
            _asset,
            string(abi.encodePacked("Bay ", _name, " Vault")),
            string(abi.encodePacked("bay", _symbol))
        )
    {
        // Prevent minting of bayTokens until
        // the initialize function is called.
        totalSupply = type(uint256).max;

        bayTreasury = _bayTreasury;
    }

    modifier whenInitialized() {
        if (totalSupply == type(uint256).max) revert NotInitialized();
        _;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Initialize the vault and set the active strategy.
    function initialize(BayStrategy strategy) external onlyOwner whenNotPaused {
        // Ensure the Vault has not already been initialized.
        if (totalSupply != type(uint256).max) revert AlreadyInitialized();

        _setActiveStrategy(strategy);

        // Open for deposits.
        totalSupply = 0;

        emit Initialized(msg.sender, address(activeStrategy));
    }

    /// @notice Add a new BayStrategy
    /// @dev Calls strategyInfo() to verify the new strategy implements required interface
    /// @param strategy new strategy
    /// @return id of added strategy
    function addStrategy(BayStrategy strategy)
        external
        onlyOwner
        returns (uint256 id)
    {
        if (!strategies.add(address(strategy))) revert DuplicateStrategy();

        id = strategies.length() - 1;
        ERC20 depositToken = strategy.depositToken();
        strategyIdsForDepositToken[address(depositToken)].push(id);
        strategyIdForStrategyAddress[address(strategy)] = id;

        emit AddStrategy(id, address(strategy));
    }

    /// @notice Checks whether the specified strategy is enabled
    /// for this vault, and not paused.
    function isEnabledStrategy(BayStrategy strategy)
        public
        view
        returns (bool)
    {
        return strategies.contains(address(strategy)) && !strategy.paused();
    }

    function strategiesForDepositTokenCount(address _depositToken)
        external
        view
        returns (uint256)
    {
        return strategyIdsForDepositToken[_depositToken].length;
    }

    function strategyId(address _strategy) external view returns (uint256) {
        return strategyIdForStrategyAddress[_strategy];
    }

    function strategiesCount() external view returns (uint256) {
        return strategies.length();
    }

    /// @notice Set the active strategy for the vault.
    /// @param strategy Set as the updated strategy.
    function setActiveStrategy(BayStrategy strategy)
        public
        onlyOwner
        whenNotPaused
    {
        _setActiveStrategy(strategy);
    }

    function _setActiveStrategy(BayStrategy strategy) internal {
        if (!isEnabledStrategy(strategy)) revert StrategyNotEnabled();
        if (asset != strategy.depositToken()) revert InvalidDepositToken();

        activeStrategy = strategy;
        emit SetActiveStrategy(address(strategy));
    }

    /// @notice Deposit a specific amount of underlying tokens.
    /// bayTokens are minted and assigned to the account on receipt of
    /// underlying tokens.
    /// @dev Vaults may allow multiple types of tokens to be deposited
    /// @dev By default, Vaults send new deposits to the active strategy
    /// @param amount The amount of underlying tokens to deposit.
    /// @param account The account to whom the bayTokens should be assigned.
    function deposit(uint256 amount, address account)
        public
        virtual
        override
        whenNotPaused
        whenInitialized
        returns (uint256 shares)
    {
        shares = ERC4626.deposit(amount, account);
    }

    /// @notice Deposits funds to the active strategy.
    /// @dev Called inside the ERC4626 deposit function.
    /// @param amount The amount of underlying tokens to deposit.
    function afterDeposit(uint256 amount, uint256) internal virtual override {
        asset.safeTransfer(address(activeStrategy), amount);
        activeStrategy.deposit(amount);
    }

    /// @notice Mints a specific amount of shares.
    /// bayTokens are minted and assigned to the account on receipt of
    /// underlying tokens.
    /// @dev Vaults may allow multiple types of tokens to be deposited
    /// @dev By default, Vaults send new deposits to the active strategy
    /// @param shares Number of shares the account wishes to mint.
    /// @param account The account to whom the bayTokens should be assigned.
    /// @return amount The amount of underlying tokens transferred.
    function mint(uint256 shares, address account)
        public
        virtual
        override
        whenNotPaused
        whenInitialized
        returns (uint256 amount)
    {
        amount = ERC4626.mint(shares, account);
    }

    /// @notice Withdraw a specific amount of underlying tokens.
    /// @param amount The amount of underlying tokens to withdraw.
    /// @param to The account to send the underlying tokens to.
    /// @param from The account which owns the bayTokens.
    function withdraw(
        uint256 amount,
        address to,
        address from
    )
        public
        virtual
        override
        whenNotPaused
        whenInitialized
        returns (uint256 shares)
    {
        shares = ERC4626.withdraw(amount, to, from);
    }

    /// @notice Withdraws funds from the active strategy.
    /// @dev Called inside the ERC4626 withdraw/redeem functions.
    /// @param amount The amount of underlying tokens to withdraw.
    function beforeWithdraw(uint256 amount, uint256) internal virtual override {
        uint256 liquidDeposits = asset.balanceOf(address(this));

        if (liquidDeposits < amount) {
            uint256 _withdraw = amount - liquidDeposits;
            BayStrategy(activeStrategy).withdraw(_withdraw);
            uint256 _after = asset.balanceOf(address(this));
            uint256 _diff = _after - liquidDeposits;
            if (_diff < _withdraw) {
                amount = liquidDeposits + _diff;
            }
        }
    }

    /// @notice Redeem a specific amount of bayTokens for underlying tokens.
    /// @param shares The amount of bayTokens to redeem for underlying tokens.
    /// @param to The account to send the underlying tokens to.
    /// @param from The account which owns the bayTokens.
    function redeem(
        uint256 shares,
        address to,
        address from
    )
        public
        virtual
        override
        whenNotPaused
        whenInitialized
        returns (uint256 amount)
    {
        amount = ERC4626.redeem(shares, to, from);
    }

    function available() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice Balance of the underlying asset in the Vault.
    /// This is the sum of asset balance in the vault and strategy.
    function totalAssets() public view virtual override returns (uint256) {
        return
            asset.balanceOf(address(this)) +
            BayStrategy(activeStrategy).balance();
    }

    function pricePerShare() public view returns (uint256) {
        return
            totalSupply == 0 ? 1e18 : (totalAssets() * (1e18)) / (totalSupply);
    }
}
