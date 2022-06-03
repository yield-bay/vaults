// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {BayRouter} from "src/BayRouter.sol";
import {BayStrategy} from "src/BayStrategy.sol";
import {BayVault} from "src/BayVault.sol";
import {BayVaultFactory} from "src/BayVaultFactory.sol";
import {SolarStrategy} from "src/strategies/solar/SolarStrategy.sol";
import {WarpInV1} from "src/warp/WarpIn.sol";
import {WarpOutV1} from "src/warp/WarpOut.sol";
import {ISolarDistributorV2, SolarDistributor} from "src/interface/solar/ISolarDistributorV2.sol";
import {ISolarRouter02} from "src/interface/solar/ISolarRouter02.sol";
import {ISolarPair} from "src/interface/solar/ISolarPair.sol";
import {ISolarFactory} from "src/interface/solar/ISolarFactory.sol";
import {IWETH} from "src/interface/solar/IWETH.sol";
import {IYieldBayWarpIn} from "src/interface/warp/IYieldBayWarpIn.sol";
import {IYieldBayWarpOut} from "src/interface/warp/IYieldBayWarpOut.sol";
import {Utils} from "src/lib/Utils.sol";
import {BaseTest} from "../BaseTest.sol";
import "src/lib/constants.sol";

contract SolarStrategyTest is BaseTest {
    struct Contracts {
        BayVaultFactory vaultFactory;
        SolarStrategy strategy;
        BayVault vault;
        BayRouter bayRouter;
        WarpInV1 warpIn;
        WarpOutV1 warpOut;
        ISolarRouter02 solarRouter;
        ISolarFactory solarFactory;
        ISolarPair solarPair;
        ISolarDistributorV2 solarDistributor;
    }

    Contracts contracts;

    struct Paths {
        address[] outputToLp0Route;
        address[] outputToLp1Route;
        address[] outputToNativeRoute;
        address[] movrToUsdcRoute;
        address[] usdcToMovrRoute;
        address[] movrToDaiRoute;
        address[] daiToMovrRoute;
        address[] daiToUsdcRoute;
        address[] empty;
    }

    Paths paths;

    struct Underlying {
        ERC20 asset;
        string name;
        string symbol;
        uint256 poolId;
    }

    Underlying underlying;

    address public bayTreasury;
    address public vaultFactoryOwner;
    address public vaultOwner;
    address public strategyOwner;
    address public bayRouterOwner;
    address public strategist;
    address public user1;
    address public user2;
    address public harvestooor;

    uint256 public delay = 1000 seconds;

    function setUp() public {
        contracts.solarDistributor = ISolarDistributorV2(
            SOLARBEAM_DISTRIBUTOR_V2
        );
        contracts.solarFactory = ISolarFactory(SOLARBEAM_FACTORY);
        contracts.solarRouter = ISolarRouter02(SOLARBEAM_ROUTER);
        // contracts.solarPair = ISolarPair(MOVR_USDC_LP);
        contracts.solarPair = ISolarPair(DAI_USDC_LP);

        contracts.warpIn = new WarpInV1(
            contracts.solarRouter,
            contracts.solarFactory,
            IWETH(WMOVR)
        );
        contracts.warpOut = new WarpOutV1(contracts.solarRouter, IWETH(WMOVR));

        // paths.outputToLp0Route = [SOLAR, WMOVR];
        // paths.outputToLp1Route = [SOLAR, USDC];
        // paths.outputToNativeRoute = [SOLAR, WMOVR];
        paths.outputToLp0Route = [SOLAR, USDC, DAI];
        paths.outputToLp1Route = [SOLAR, USDC];
        paths.outputToNativeRoute = [SOLAR, WMOVR];

        paths.movrToUsdcRoute = [WMOVR, USDC];
        paths.usdcToMovrRoute = [USDC, WMOVR];
        paths.movrToDaiRoute = [WMOVR, USDC, DAI];
        paths.daiToMovrRoute = [DAI, USDC, WMOVR];
        paths.daiToUsdcRoute = [DAI, USDC];
        paths.empty = new address[](0);

        bayTreasury = vm.addr(1);
        vaultFactoryOwner = vm.addr(2);
        vaultOwner = vm.addr(3);
        strategyOwner = vm.addr(4);
        bayRouterOwner = vm.addr(5);
        strategist = strategyOwner;
        user1 = vm.addr(6);
        user2 = vm.addr(7);
        harvestooor = vm.addr(8);

        vm.label(SOLAR, "SOLAR");
        vm.label(USDC, "USDC");
        vm.label(DAI, "DAI");
        vm.label(WMOVR, "WMOVR");
        vm.label(address(contracts.solarDistributor), "solarDistributor");
        vm.label(address(contracts.solarFactory), "solarFactory");
        vm.label(address(contracts.solarRouter), "solarRouter");
        vm.label(address(contracts.solarPair), "solarPair");
        vm.label(address(contracts.warpIn), "warpIn");
        vm.label(address(contracts.warpOut), "warpOut");
        vm.label(bayTreasury, "bayTreasury");
        vm.label(vaultFactoryOwner, "vaultFactoryOwner");
        vm.label(vaultOwner, "vaultOwner");
        vm.label(strategyOwner, "strategyOwner");
        vm.label(strategist, "strategist");
        vm.label(user1, "user1");
        vm.label(user2, "user2");
        vm.label(harvestooor, "harvestooor");

        // underlying = ERC20(MOVR_USDC_LP);
        // underlying = ERC20(DAI_USDC_LP);
        underlying.asset = ERC20(DAI_USDC_LP);
        underlying.name = "DAI-USDC LP";
        underlying.symbol = "DAI-USDC";
        underlying.poolId = 26;
        vm.label(address(underlying.asset), "underlyingLP");

        hoax(vaultFactoryOwner);
        contracts.vaultFactory = new BayVaultFactory();
        vm.label(address(contracts.vaultFactory), "vaultFactory");
        hoax(vaultOwner);
        contracts.vault = contracts.vaultFactory.deployVault(
            underlying.asset,
            underlying.name,
            underlying.symbol,
            bayTreasury
        );
        vm.label(address(contracts.vault), "vault");
        hoax(address(strategyOwner));
        contracts.strategy = new SolarStrategy(
            underlying.poolId,
            contracts.vault,
            contracts.solarRouter,
            contracts.solarDistributor,
            IYieldBayWarpIn(address(contracts.warpIn)),
            paths.outputToNativeRoute,
            paths.outputToLp0Route,
            paths.outputToLp1Route
        );
        vm.label(address(contracts.strategy), "strategy");
        hoax(address(bayRouterOwner));
        contracts.bayRouter = new BayRouter(
            contracts.solarRouter,
            contracts.solarFactory,
            IWETH(WMOVR)
        );
        vm.label(address(contracts.bayRouter), "bayRouter");

        assertEq(contracts.vault.totalSupply(), type(uint256).max);
        startHoax(address(vaultOwner));
        uint256 stratId = contracts.vault.addStrategy(contracts.strategy);
        assertEq(stratId, 0);
        contracts.vault.initialize(contracts.strategy);

        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                        MISC SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    function testFailPauseVault() public {
        hoax(user1);
        contracts.vault.pause();
    }

    function testFailUnpauseVault() public {
        hoax(vaultOwner);
        contracts.vault.pause();
        hoax(user1);
        contracts.vault.unpause();
    }

    function testFailAddStrategyNotVaultOwner() public {
        hoax(user1);
        contracts.vault.addStrategy(contracts.strategy);
    }

    function testFailAddDuplicateStrategy() public {
        hoax(vaultOwner);
        contracts.vault.addStrategy(contracts.strategy);
    }

    function testFailSetActiveStrategyWhenPaused() public {
        hoax(vaultOwner);
        contracts.vault.pause();
        contracts.vault.setActiveStrategy(contracts.strategy);
    }

    function testFailSetActiveStrategyNotVaultOwner() public {
        hoax(user1);
        contracts.vault.setActiveStrategy(contracts.strategy);
    }

    /*///////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testAtomicMint() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        contracts.solarPair.approve(
            address(contracts.vault),
            type(uint256).max
        );
        uint256 oldSolarPairBal = contracts.solarPair.balanceOf(user1);
        uint256 amount = contracts.vault.mint(1e18, user1);
        assertGt(amount, 0);
        assertEq(contracts.vault.balanceOf(user1), 1e18);
        assertGt(oldSolarPairBal, contracts.solarPair.balanceOf(user1));

        (uint256 vaultAmount, , , ) = contracts.solarDistributor.userInfo(
            underlying.poolId,
            address(contracts.strategy)
        );
        assertEq(vaultAmount, amount);
        assertEq(vaultAmount, contracts.strategy.balance());

        vm.stopPrank();
    }

    function testAtomicDepositWithdraw() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        contracts.solarPair.approve(
            address(contracts.vault),
            type(uint256).max
        );
        uint256 amount = contracts.solarPair.balanceOf(user1);
        uint256 shares = contracts.vault.deposit(amount, user1);
        assertGt(shares, 0);
        assertEq(contracts.vault.balanceOf(user1), shares);
        assertEq(contracts.solarPair.balanceOf(user1), 0);

        (uint256 vaultAmount, , , ) = contracts.solarDistributor.userInfo(
            underlying.poolId,
            address(contracts.strategy)
        );
        assertEq(vaultAmount, amount);
        assertEq(vaultAmount, contracts.strategy.balance());

        contracts.vault.withdraw(amount, user1, user1);

        assertEq(contracts.vault.balanceOf(user1), 0);
        assertEq(contracts.solarPair.balanceOf(user1), amount);

        (uint256 vaultAmountAfterWithdrawal, , , ) = contracts
            .solarDistributor
            .userInfo(underlying.poolId, address(contracts.strategy));
        assertEq(vaultAmountAfterWithdrawal, 0);
        assertEq(vaultAmountAfterWithdrawal, contracts.strategy.balance());

        vm.stopPrank();
    }

    function testAtomicDepositRedeem() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        contracts.solarPair.approve(
            address(contracts.vault),
            type(uint256).max
        );
        uint256 amount = contracts.solarPair.balanceOf(user1);
        uint256 shares = contracts.vault.deposit(amount, user1);
        assertGt(shares, 0);
        assertEq(contracts.vault.balanceOf(user1), shares);
        assertEq(contracts.solarPair.balanceOf(user1), 0);

        (uint256 vaultAmount, , , ) = contracts.solarDistributor.userInfo(
            underlying.poolId,
            address(contracts.strategy)
        );
        assertEq(vaultAmount, amount);
        assertEq(vaultAmount, contracts.strategy.balance());

        contracts.vault.redeem(shares, user1, user1);

        assertEq(contracts.vault.balanceOf(user1), 0);
        assertEq(contracts.solarPair.balanceOf(user1), amount);

        (uint256 vaultAmountAfterWithdrawal, , , ) = contracts
            .solarDistributor
            .userInfo(underlying.poolId, address(contracts.strategy));
        assertEq(vaultAmountAfterWithdrawal, 0);
        assertEq(vaultAmountAfterWithdrawal, contracts.strategy.balance());

        vm.stopPrank();
    }

    function testRouterWarpInFromERC20() public {
        startHoax(user1, 10 ether);
        tip(DAI, user1, 10 ether);
        IERC20(DAI).approve(address(contracts.bayRouter), type(uint256).max);
        uint256 shares = contracts.bayRouter.warpIn(
            contracts.vault,
            IERC20(DAI),
            paths.empty,
            paths.daiToUsdcRoute,
            3 ether,
            5,
            address(contracts.warpIn)
        );

        assertGt(contracts.vault.totalAssets(), 0);
        assertEq(contracts.vault.totalAssets(), shares);
        assertEq(contracts.vault.pricePerShare(), 1e18);

        vm.stopPrank();
    }

    function testRouterWarpInFromMovr() public {
        startHoax(user1, 10 ether);
        uint256 shares = contracts.bayRouter.warpIn{value: 3 ether}(
            contracts.vault,
            IERC20(address(0)),
            paths.movrToDaiRoute,
            paths.movrToUsdcRoute,
            3 ether,
            5,
            address(contracts.warpIn)
        );

        assertGt(contracts.vault.totalAssets(), 0);
        assertEq(contracts.vault.totalAssets(), shares);
        assertEq(contracts.vault.pricePerShare(), 1e18);

        vm.stopPrank();
    }

    function testRouterWarpOutToERC20() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        contracts.solarPair.approve(
            address(contracts.vault),
            type(uint256).max
        );
        uint256 amount = contracts.solarPair.balanceOf(user1);
        uint256 shares = contracts.vault.deposit(amount, user1);

        contracts.vault.approve(
            address(contracts.bayRouter),
            type(uint256).max
        ); // shares);
        // contracts.vault.approve(address(contracts.warpOut), type(uint256).max); // shares);
        contracts.bayRouter.warpOut(
            contracts.vault,
            IERC20(USDC),
            paths.daiToUsdcRoute,
            paths.empty,
            shares,
            address(contracts.warpOut)
        );
    }

    function testRouterWarpOutToMovr() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        contracts.solarPair.approve(
            address(contracts.vault),
            type(uint256).max
        );
        uint256 amount = contracts.solarPair.balanceOf(user1);
        uint256 shares = contracts.vault.deposit(amount, user1);

        contracts.vault.approve(
            address(contracts.bayRouter),
            type(uint256).max
        ); // shares);
        // contracts.vault.approve(address(contracts.warpOut), type(uint256).max); // shares);
        contracts.bayRouter.warpOut(
            contracts.vault,
            IERC20(address(0)),
            paths.daiToMovrRoute,
            paths.usdcToMovrRoute,
            shares,
            address(contracts.warpOut)
        );
    }

    /*///////////////////////////////////////////////////////////////
                 DEPOSIT/WITHDRAWAL SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    function testFailDepositWhenPaused() public {
        hoax(vaultOwner);
        contracts.vault.pause();

        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        contracts.solarPair.approve(
            address(contracts.vault),
            type(uint256).max
        );
        contracts.vault.deposit(contracts.solarPair.balanceOf(user1), user1);

        vm.stopPrank();
    }

    function testFailMintWhenPaused() public {
        hoax(vaultOwner);
        contracts.vault.pause();

        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        contracts.solarPair.approve(
            address(contracts.vault),
            type(uint256).max
        );
        contracts.vault.mint(1e18, user1);

        vm.stopPrank();
    }

    function testFailWithdrawWhenPaused() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        contracts.solarPair.approve(
            address(contracts.vault),
            type(uint256).max
        );
        uint256 amount = contracts.solarPair.balanceOf(user1);
        contracts.vault.deposit(amount, user1);

        vm.stopPrank();

        hoax(vaultOwner);
        contracts.vault.pause();

        contracts.vault.withdraw(amount, user1, user1);

        vm.stopPrank();
    }

    function testFailRedeemWhenPaused() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        contracts.solarPair.approve(
            address(contracts.vault),
            type(uint256).max
        );
        uint256 amount = contracts.solarPair.balanceOf(user1);
        uint256 shares = contracts.vault.deposit(amount, user1);

        vm.stopPrank();

        hoax(vaultOwner);
        contracts.vault.pause();

        contracts.vault.redeem(shares, user1, user1);

        vm.stopPrank();
    }

    function testFailDepositWithNotEnoughApproval() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        uint256 amount = contracts.solarPair.balanceOf(user1);
        contracts.solarPair.approve(address(contracts.vault), amount - 1);
        contracts.vault.deposit(amount, user1);

        vm.stopPrank();
    }

    function testFailMintWithNotEnoughApproval() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        contracts.solarPair.approve(address(contracts.vault), 0);
        contracts.vault.mint(1e18, user1);

        vm.stopPrank();
    }

    function testFailDepositWithNoApproval() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        uint256 amount = contracts.solarPair.balanceOf(user1);
        contracts.vault.deposit(amount, user1);

        vm.stopPrank();
    }

    function testFailMintWithNoApproval() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        contracts.vault.mint(1e18, user1);

        vm.stopPrank();
    }

    function testFailWithdrawWithNotEnoughBalance() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        contracts.solarPair.approve(
            address(contracts.vault),
            type(uint256).max
        );
        uint256 amount = contracts.solarPair.balanceOf(user1);
        contracts.vault.deposit(amount, user1);

        contracts.vault.withdraw(amount + 1, user1, user1);

        vm.stopPrank();
    }

    function testFailRedeemWithNotEnoughBalance() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);
        contracts.solarPair.approve(
            address(contracts.vault),
            type(uint256).max
        );
        uint256 amount = contracts.solarPair.balanceOf(user1);
        uint256 shares = contracts.vault.deposit(amount, user1);

        contracts.vault.redeem(shares + 1, user1, user1);

        vm.stopPrank();
    }

    function testFailWithdrawWithNoBalance() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);

        uint256 amount = contracts.solarPair.balanceOf(user1);

        contracts.vault.withdraw(amount, user1, user1);

        vm.stopPrank();
    }

    function testFailRedeemWithNoBalance() public {
        startHoax(user1);
        tip(address(contracts.solarPair), user1, 10 ether);

        contracts.vault.redeem(1e18, user1, user1);

        vm.stopPrank();
    }

    /*///////////////////////////////////////////////////////////////
                             HARVEST TESTS
    //////////////////////////////////////////////////////////////*/

    function testProfitableHarvest() public {
        startHoax(user1, 10 ether);
        uint256 shares = contracts.bayRouter.warpIn{value: 3 ether}(
            contracts.vault,
            IERC20(address(0)),
            // paths.empty,
            // paths.movrToUsdcRoute,
            paths.movrToDaiRoute,
            paths.movrToUsdcRoute,
            3 ether,
            5,
            address(contracts.warpIn)
        );

        emit log_named_uint("shares bought using $NATIVE", shares);
        emit log_named_uint(
            "treasury native bal before harvest",
            IWETH(WMOVR).balanceOf(bayTreasury)
        );

        emit log_named_uint("btimestamp", block.timestamp);

        emit log_named_uint("lastHarvest", contracts.strategy.lastHarvest());
        emit log_named_uint("totalAssets", contracts.vault.totalAssets());
        emit log_named_uint("available", contracts.vault.available());

        uint256 vaultBalance = contracts.vault.totalAssets();
        uint256 pricePerFullShare = contracts.vault.pricePerShare();
        uint256 lastHarvest = contracts.strategy.lastHarvest();
        emit log_named_uint("vaultBalance", vaultBalance);
        emit log_named_uint("pricePerFullShare", pricePerFullShare);
        emit log_named_uint("lastHarvest", lastHarvest);

        assertEq(lastHarvest, 0);

        shift(delay);

        emit log("Harvesting vault.");
        bool didHarvest = _harvest(harvestooor);
        assertTrue(didHarvest, "Harvest failed.");

        uint256 vaultBalanceAfterHarvest = contracts.vault.totalAssets();
        uint256 pricePerFullShareAfterHarvest = contracts.vault.pricePerShare();
        uint256 lastHarvestAfterHarvest = contracts.strategy.lastHarvest();
        emit log_named_uint(
            "vaultBalanceAfterHarvest",
            vaultBalanceAfterHarvest
        );
        emit log_named_uint(
            "pricePerFullShareAfterHarvest",
            pricePerFullShareAfterHarvest
        );
        emit log_named_uint("lastHarvestAfterHarvest", lastHarvestAfterHarvest);

        emit log_named_uint(
            "treasury native bal after harvest",
            IWETH(WMOVR).balanceOf(bayTreasury)
        );

        assertGt(vaultBalanceAfterHarvest, vaultBalance);
        assertGt(pricePerFullShareAfterHarvest, pricePerFullShare);
        assertGt(IWETH(WMOVR).balanceOf(bayTreasury), 0);

        // assertGt(vaultBalance, vaultBalanceAfterHarvest);
        // assertGt(pricePerFullShare, pricePerFullShareAfterHarvest);
        // assertGt(0, IWETH(WMOVR).balanceOf(bayTreasury));

        shift(delay);

        emit log("Harvesting vault2.");
        bool didHarvest2 = _harvest(harvestooor);
        assertTrue(didHarvest2, "Harvest failed2.");

        uint256 vaultBalanceAfterHarvest2 = contracts.vault.totalAssets();
        uint256 pricePerFullShareAfterHarvest2 = contracts
            .vault
            .pricePerShare();
        uint256 lastHarvestAfterHarvest2 = contracts.strategy.lastHarvest();
        emit log_named_uint(
            "vaultBalanceAfterHarvest2",
            vaultBalanceAfterHarvest2
        );
        emit log_named_uint(
            "pricePerFullShareAfterHarvest2",
            pricePerFullShareAfterHarvest2
        );
        emit log_named_uint(
            "lastHarvestAfterHarvest2",
            lastHarvestAfterHarvest2
        );

        emit log_named_uint(
            "treasury native bal after harvest2",
            IWETH(WMOVR).balanceOf(bayTreasury)
        );

        vm.stopPrank();
    }

    function testUnprofitableHarvest() public {}

    function testMultipleHarvestsInWindow() public {}

    /*///////////////////////////////////////////////////////////////
                        HARVEST SANITY CHECK TESTS
    //////////////////////////////////////////////////////////////*/

    /*///////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _harvest(address user) internal returns (bool didHarvest_) {
        // Retry a few times
        uint256 retryTimes = 1;
        for (uint256 i = 0; i < retryTimes; i++) {
            try contracts.strategy.harvest(address(user)) {
                didHarvest_ = true;
                break;
            } catch Error(string memory reason) {
                emit log_named_string("Harvest failed with reason:", reason);
            } catch Panic(uint256 errorCode) {
                emit log_named_uint(
                    "Harvest panicked, failed with errorCode:",
                    errorCode
                );
            } catch (bytes memory) {
                emit log("Harvest failed.");
            }
            if (i != retryTimes - 1) {
                emit log("Trying harvest again.");
                shift(delay);
            }
        }
    }
}

contract UnInitializedVaultTest is BaseTest {
    // function testFailDepositWhenNotInitialized() public {}
}
