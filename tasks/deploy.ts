import { ethers } from "hardhat";

import { ROUTER, FACTORY, WMOVR, DAI_USDC_LP, SOLAR_DISTRIBUTOR_V2 } from "./constants";
import * as data from "../raw/solarChef.json"
import sdv2 from "../raw/sdv2.json"

(async function main() {
    // Hardhat always runs the compile task when running scripts with its command
    // line interface.
    //
    // If this script is run directly using `node` you may want to call compile
    // manually to make sure everything is compiled
    // await hre.run('compile');

    const signers = await ethers.getSigners();

    const WarpInV1 = await ethers.getContractFactory("WarpInV1");
    const warpInV1 = await WarpInV1.deploy(ROUTER, FACTORY, WMOVR);

    await warpInV1.deployed();
    console.log("warpInV1", warpInV1.address);


    const WarpOutV1 = await ethers.getContractFactory("WarpOutV1");
    const warpOutV1 = await WarpOutV1.deploy(ROUTER, WMOVR);

    await warpOutV1.deployed();
    console.log("warpOutV1", warpOutV1.address);

    const BayVaultFactory = await ethers.getContractFactory("BayVaultFactory");
    const bayVaultFactory = await BayVaultFactory.deploy();

    await bayVaultFactory.deployed();
    console.log("bayVaultFactory", bayVaultFactory.address);

    // const bayTreasury = bayVaultFactory.address;
    const bayTreasury = signers[0].address;

    const Bay = await ethers.getContractFactory("Bay");
    const bay = await Bay.deploy("BayTM", "BAYTM", 18);

    await bay.deployed();
    console.log("bay", bay.address);


    const BayChef = await ethers.getContractFactory("BayChef");
    const bayChef = await BayChef.deploy(
        bayVaultFactory.address,
        bay.address,
        420,
        signers[1].address,
        signers[1].address,
        signers[1].address,
        10,
        5,
        15
    );

    await bayChef.deployed();
    console.log("bayChef", bayChef.address);


    const farms = (<any>data).default;
    farms.forEach(async (f: any) => {
        // console.log("frm", f, f[1].split(" ")[0]);
        if (f[1].split(" ")[0] !== "stable" && f[1].split(" ")[0] !== "vesolar" && f[1] !== "wmovr") {
            console.log("f", f[0], f[1], f[2], bayTreasury);

            const vault = await bayVaultFactory.callStatic.deployVault(f[2], f[1] + " LP", f[1], bayTreasury);
            console.log("vault", vault);

            // const dvtxn = await bayVaultFactory.deployVault(f[2], f[1] + " LP", f[1], bayTreasury);
            // const va = await dvtxn.wait();

            // const MultiRewardStrat = await ethers.getContractFactory("MultiRewardStrat");
        }
    })
})()
