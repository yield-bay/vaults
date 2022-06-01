// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISolarDistributorV2, SolarDistributor} from "../../interface/solar/ISolarDistributorV2.sol";
import {ISolarPair} from "../../interface/solar/ISolarPair.sol";
import {ISolarRouter02} from "../../interface/solar/ISolarRouter02.sol";
import {IComplexRewarder} from "../../interface/solar/IComplexRewarder.sol";
import {IYieldBayWarpIn} from "../../interface/warp/IYieldBayWarpIn.sol";
import {IYieldBayWarpOut} from "../../interface/warp/IYieldBayWarpOut.sol";
import {BayStrategy} from "../../BayStrategy.sol";
import {BayVault} from "../../BayVault.sol";
import {Utils} from "../../lib/Utils.sol";
import "../../lib/errors.sol";
import "../../lib/constants.sol";

/// @author Jack Sparrow from YieldBay
/// @notice Strategy contract for solarbeam LP farms.
contract MultiRewardStrat is BayStrategy {
    using SafeTransferLib for ERC20;
    using SafeERC20 for IERC20;

    /// @notice The native token of the network, i.e., $WMOVR or $WGLMR.
    IERC20 public native;

    /// @notice The output token of the farm, i.e., $SOLAR or $FLARE.
    IERC20 public output;

    /// @notice List of rewarders.
    /// @dev Provides rewards other than $SOLAR or $FLARE.
    IComplexRewarder[] public rewarders;

    struct RewardRoutes {
        address[] rewardToNativeRoute;
        address[] rewardToLp0Route;
        address[] rewardToLp1Route;
    }

    mapping(uint256 => RewardRoutes) rewardRoutesForRewarder;

    struct LP {
        address token0;
        address token1;
    }

    LP public lp;

    /// @notice Adddress of the SolarDistributor contract.
    ISolarDistributorV2 public chef;

    /// @notice Adddress of the SolarRouter contract.
    ISolarRouter02 public router;

    /// @notice Address of the YieldBay WarpIn contract.
    IYieldBayWarpIn public warpIn;

    /// @notice Id of the pool/farm.
    uint256 public poolId;

    /// @notice Indicates if rewards should be harvested on deposit.
    bool public harvestOnDeposit = true;

    /// @notice Timestamp when rewards were last harvested.
    uint256 public lastHarvest;

    /// @notice Slippage percentage for warping in liquidity using harvests.
    uint256 public slippage = 10;

    // Routes
    address[] public outputToNativeRoute;
    address[] public outputToLp0Route;
    address[] public outputToLp1Route;

    event StratDeposit(uint256 indexed poolId, uint256 indexed amount);
    event StratWithdraw(uint256 indexed poolId, uint256 indexed amount);
    event StratHarvest(
        uint256 poolId,
        address harvester,
        address indexed harvestRewardRecipient,
        uint256 liquidityAdded,
        uint256 indexed depositTokenHarvested,
        uint256 indexed tvl
    );

    constructor(
        uint256 _poolId,
        BayVault _vault,
        ISolarRouter02 _router,
        ISolarDistributorV2 _chef,
        IYieldBayWarpIn _warpIn,
        address[] memory _outputToNativeRoute,
        address[] memory _outputToLp0Route,
        address[] memory _outputToLp1Route,
        IComplexRewarder[] memory _rewarders
    ) BayStrategy(_vault) {
        poolId = _poolId;
        vault = _vault;
        router = _router;
        chef = _chef;
        warpIn = _warpIn;
        depositToken = _vault.asset();
        strategist = msg.sender;

        output = IERC20(_outputToNativeRoute[0]);
        native = IERC20(_outputToNativeRoute[_outputToNativeRoute.length - 1]);
        outputToNativeRoute = _outputToNativeRoute;

        // setup lp routing
        lp.token0 = ISolarPair(address(depositToken)).token0();

        if (_outputToLp0Route[0] != address(output))
            revert InvalidRoute("outputToLp0Route[0] != output");
        if (_outputToLp0Route[_outputToLp0Route.length - 1] != lp.token0)
            revert InvalidRoute("outputToLp0Route[last] != lp.token0");

        outputToLp0Route = _outputToLp0Route;

        lp.token1 = ISolarPair(address(depositToken)).token1();

        if (_outputToLp1Route[0] != address(output))
            revert InvalidRoute("outputToLp1Route[0] != output");
        if (_outputToLp1Route[_outputToLp1Route.length - 1] != lp.token1)
            revert InvalidRoute("outputToLp1Route[last] != lp.token1");

        outputToLp1Route = _outputToLp1Route;

        rewarders = _rewarders;

        _giveAllowances();
    }

    function _giveAllowances() internal virtual override {
        depositToken.approve(address(chef), MAX_UINT);
        output.approve(address(router), MAX_UINT);

        IERC20(lp.token0).approve(address(router), 0);
        IERC20(lp.token0).approve(address(router), MAX_UINT);

        IERC20(lp.token1).approve(address(router), 0);
        IERC20(lp.token1).approve(address(router), MAX_UINT);
    }

    function _removeAllowances() internal virtual override {
        depositToken.approve(address(chef), 0);
        output.approve(address(router), 0);

        IERC20(lp.token0).approve(address(router), 0);
        IERC20(lp.token1).approve(address(router), 0);
    }

    /// @notice Called as part of strategy migration.
    /// Sends all the available funds back to the vault.
    function retireStrat() external virtual override onlyVault {
        ISolarDistributorV2(chef).emergencyWithdraw(poolId);

        uint256 depositTokenBal = depositToken.balanceOf(address(this));
        depositToken.safeTransfer(address(vault), depositTokenBal);
    }

    /// @notice Pauses deposits and withdraws all funds from third party systems.
    function panic() external virtual override onlyOwner {
        pause();
        ISolarDistributorV2(chef).emergencyWithdraw(poolId);
    }

    function pause() public virtual override onlyOwner {
        _pause();

        _removeAllowances();
    }

    function unpause() external virtual override onlyOwner {
        _unpause();

        _giveAllowances();

        depositAll();
    }

    function deposit(uint256 amount)
        external
        virtual
        override
        onlyVault
        whenNotPaused
    {
        beforeDeposit(strategist);

        try ISolarDistributorV2(chef).deposit(poolId, amount) {
            emit StratDeposit(poolId, amount);
        } catch Error(string memory reason) {
            if (depositToken.balanceOf(address(this)) < amount)
                revert InsufficientBalance();
            else if (depositToken.allowance(address(this), msg.sender) < amount)
                revert InsufficientAllowance();
            else revert(reason);
        }
    }

    function depositAll() public virtual override onlyVault whenNotPaused {
        beforeDeposit(strategist);

        uint256 depositTokenBal = depositToken.balanceOf(address(this));

        try ISolarDistributorV2(chef).deposit(poolId, depositTokenBal) {
            emit StratDeposit(poolId, depositTokenBal);
        } catch Error(string memory reason) {
            if (
                depositToken.allowance(address(this), msg.sender) <
                depositTokenBal
            ) revert InsufficientAllowance();
            else revert(reason);
        }
    }

    function withdraw(uint256 amount)
        external
        virtual
        override
        onlyVault
        whenNotPaused
    {
        uint256 depositTokenBal = depositToken.balanceOf(address(this));

        if (depositTokenBal < amount) {
            ISolarDistributorV2(chef).withdraw(
                poolId,
                amount - depositTokenBal
            );
            depositTokenBal = depositToken.balanceOf(address(this));
        }

        if (depositTokenBal > amount) {
            depositTokenBal = amount;
        }

        depositToken.safeTransfer(address(vault), depositTokenBal);
        emit StratWithdraw(poolId, depositTokenBal);
    }

    function withdrawAll() external virtual override onlyVault whenNotPaused {
        (uint256 bal, , , ) = ISolarDistributorV2(chef).userInfo(
            poolId,
            address(this)
        );
        if (bal > 0) {
            ISolarDistributorV2(chef).withdraw(poolId, bal);
            bal = depositToken.balanceOf(address(this));
            depositToken.safeTransfer(address(vault), bal);
            emit StratWithdraw(poolId, bal);
        }
    }

    function harvest(address harvestRewardRecipient) external virtual override {
        _harvest(harvestRewardRecipient);
    }

    /// @notice Called before depositing funds.
    function beforeDeposit(address harvestRewardRecipient)
        internal
        virtual
        override
    {
        if (harvestOnDeposit) {
            _harvest(harvestRewardRecipient);
        }
    }

    /// @notice Sends fees to the involved parties.
    /// @param harvestRewardRecipient address which invoked the harvest function.
    function chargeFees(
        address harvestRewardRecipient,
        IERC20 reward,
        address[] memory rewardToNativeRoute
    ) internal virtual override {
        uint256 totalFeeBps = harvestRewardBps + vaultFeeBps + strategistFeeBps;
        uint256 toNative = (reward.balanceOf(address(this)) * totalFeeBps) /
            BPS_DIVISOR;
        ISolarRouter02(router).swapExactTokensForTokens(
            toNative,
            0,
            rewardToNativeRoute,
            address(this),
            block.timestamp
        );

        uint256 nativeBal = IERC20(native).balanceOf(address(this));
        // console.log("chargeFees.nativeBal", nativeBal);

        uint256 callFeeAmount = (nativeBal * harvestRewardBps) / totalFeeBps;
        IERC20(native).safeTransfer(harvestRewardRecipient, callFeeAmount);

        uint256 vaultFeeAmount = (nativeBal * vaultFeeBps) / totalFeeBps;
        IERC20(native).safeTransfer(vault.bayTreasury(), vaultFeeAmount);

        uint256 strategistFee = (nativeBal * strategistFeeBps) / totalFeeBps;
        IERC20(native).safeTransfer(strategist, strategistFee);
        // console.log("chargedFees");
    }

    /// @notice Adds liquidity to AMM and gets more LP tokens.
    function addLiquidity(
        IERC20 reward,
        address[] memory rewardToLp0Route,
        address[] memory rewardToLp1Route
    ) internal returns (uint256 liquidityAdded) {
        uint256 rewardBal = reward.balanceOf(address(this));

        reward.approve(address(warpIn), 0);
        reward.approve(address(warpIn), rewardBal);

        uint256 token0Amount = rewardBal / 2;
        if (address(reward) != lp.token0)
            token0Amount = Utils.getAmountsOut(
                router,
                rewardBal / 2,
                rewardToLp0Route
            );
        uint256 token1Amount = rewardBal / 2;
        if (address(reward) != lp.token1)
            token1Amount = Utils.getAmountsOut(
                router,
                rewardBal / 2,
                rewardToLp1Route
            );
        uint256 minLP = Utils.calculateMinimumLP(
            ISolarPair(address(depositToken)),
            token0Amount,
            token1Amount,
            slippage
        );
        // console.log("beforeaddliq", rewardBal);
        liquidityAdded = IYieldBayWarpIn(warpIn).warpIn(
            reward,
            ISolarPair(address(depositToken)),
            rewardBal,
            minLP,
            rewardToLp0Route,
            rewardToLp1Route
        );
        // console.log("liqaddd", liquidityAdded);
    }

    function _harvest(address harvestRewardRecipient) internal {
        console.log("preoutputBal", output.balanceOf(address(this)));
        try ISolarDistributorV2(chef).deposit(poolId, 0) {
            console.log("sddeposit");
        } catch Error(string memory reason) {
            console.log("reason", reason);
        }
        uint256 outputBal = output.balanceOf(address(this));
        uint256 mfamBal = ISolarPair(MFAM).balanceOf(address(this));
        console.log("outputBal", outputBal, "mfambal", mfamBal);
        uint256 totalLiquidityAdded = 0;
        for (uint256 i = 0; i < rewarders.length; i++) {
            uint256 rewardTokenBal = (rewarders[i].rewardToken()).balanceOf(
                address(this)
            );
            console.log(
                "rewardToken",
                address(rewarders[i].rewardToken()),
                "rewardTokenBal",
                rewardTokenBal
            );

            if (rewardTokenBal > 0) {
                chargeFees(
                    harvestRewardRecipient,
                    IERC20(address(rewarders[i].rewardToken())),
                    rewardRoutesForRewarder[i].rewardToNativeRoute
                );
                totalLiquidityAdded += addLiquidity(
                    IERC20(address(rewarders[i].rewardToken())),
                    rewardRoutesForRewarder[i].rewardToLp0Route,
                    rewardRoutesForRewarder[i].rewardToLp1Route
                );
            }
        }
        console.log("done rwrdrs loop");
        if (outputBal > 0) {
            chargeFees(harvestRewardRecipient, output, outputToNativeRoute);
            totalLiquidityAdded += addLiquidity(
                output,
                outputToLp0Route,
                outputToLp1Route
            );
            // console.log("harvestRewardRecipient", harvestRewardRecipient);
            // console.log("liquidityAdded", liquidityAdded);
            // console.log("depositTokenHarvested", depositTokenHarvested);
        }
        uint256 depositTokenHarvested = balanceOfDeposit();
        // ISolarPair(address(depositToken)).approve()
        ISolarDistributorV2(chef).deposit(poolId, totalLiquidityAdded);
        lastHarvest = block.timestamp;
        emit StratHarvest(
            poolId,
            msg.sender,
            harvestRewardRecipient,
            totalLiquidityAdded,
            depositTokenHarvested,
            balance()
        );
    }

    /// @notice Returns the sum of depositTokens held by the strategy and working in the farm.
    function balance() public view virtual override returns (uint256) {
        return balanceOfDeposit() + balanceOfPool();
    }

    /// @notice Returns the total depositTokens held by the strategy.
    function balanceOfDeposit() public view returns (uint256) {
        return depositToken.balanceOf(address(this));
    }

    /// @notice Returns the total depositTokens the strategy has working in the farm.
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount, , , ) = ISolarDistributorV2(chef).userInfo(
            poolId,
            address(this)
        );
        return _amount;
    }

    /// @notice Pending $SOLAR rewards available
    function rewardsAvailable() public view returns (uint256) {
        return ISolarDistributorV2(chef).pendingSolar(poolId, address(this));
    }

    function updateOutputToNativeRoute(address[] memory _outputToNativeRoute)
        external
        onlyOwner
        returns (address[] memory)
    {
        return outputToNativeRoute = _outputToNativeRoute;
    }

    function updateOutputToLp0Route(address[] memory _outputToLp0Route)
        external
        onlyOwner
        returns (address[] memory)
    {
        return outputToLp0Route = _outputToLp0Route;
    }

    function updateOutputToLp1Route(address[] memory _outputToLp1Route)
        external
        onlyOwner
        returns (address[] memory)
    {
        return outputToLp1Route = _outputToLp1Route;
    }

    function updateRewardRoutesForRewarder(
        uint256 index,
        address[] memory _rewardToNativeRoute,
        address[] memory _rewardToLp0Route,
        address[] memory _rewardToLp1Route
    ) external onlyOwner {
        if (_rewardToNativeRoute.length > 0) {
            if (
                _rewardToNativeRoute[0] !=
                address(rewarders[index].rewardToken())
            ) revert InvalidRoute("_rewardToNativeRoute[0] != reward");
            if (
                _rewardToNativeRoute[_rewardToNativeRoute.length - 1] !=
                address(native)
            ) revert InvalidRoute("_rewardToNativeRoute[last] != native");
        }

        if (_rewardToLp0Route.length > 0) {
            if (_rewardToLp0Route[0] != address(rewarders[index].rewardToken()))
                revert InvalidRoute("_rewardToLp0Route[0] != reward");
            if (_rewardToLp0Route[_rewardToLp0Route.length - 1] != lp.token0)
                revert InvalidRoute("_rewardToLp0Route[last] != lp.token0");
        }

        if (_rewardToLp1Route.length > 0) {
            if (_rewardToLp1Route[0] != address(rewarders[index].rewardToken()))
                revert InvalidRoute("_rewardToLp1Route[0] != reward");
            if (_rewardToLp1Route[_rewardToLp1Route.length - 1] != lp.token1)
                revert InvalidRoute("_rewardToLp1Route[last] != lp.token1");
        }

        rewardRoutesForRewarder[index] = RewardRoutes({
            rewardToNativeRoute: _rewardToNativeRoute,
            rewardToLp0Route: _rewardToLp0Route,
            rewardToLp1Route: _rewardToLp1Route
        });
    }

    function updateSlippage(uint256 _slippage)
        external
        onlyOwner
        returns (uint256)
    {
        if (_slippage > 30) revert SlippageOutOfBounds(_slippage);
        return slippage = _slippage;
    }
}
