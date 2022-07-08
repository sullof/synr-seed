// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
require("dotenv").config();
const hre = require("hardhat");
const ethers = hre.ethers;
const DeployUtils = require("./lib/DeployUtils");
let deployUtils;
const testnetWallets = require("./testnetWallets");

async function currentChainId() {
  return (await ethers.provider.getNetwork()).chainId;
}

async function main() {
  deployUtils = new DeployUtils(ethers);
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  const chainId = await currentChainId();
  if (chainId === 1 || chainId === 56) {
    console.error("This script is for test and development only");
    process.exit();
  }

  if (chainId < 6) {
    let pass = await deployUtils.attach("SynCityPasses");
    for (let address of testnetWallets) {
      await deployUtils.Tx(pass.mint(address, 4), "Passes to " + address);
    }

    const sSynr = await deployUtils.attach("SyntheticSyndicateERC20");
    for (let address of testnetWallets) {
      await deployUtils.Tx(sSynr.mint(address, ethers.utils.parseEther("100000")), "sSYNR to " + address);
    }

    const synr = await deployUtils.attach("SyndicateERC20");
    for (let address of testnetWallets) {
      await deployUtils.Tx(synr.mint(address, ethers.utils.parseEther("100000")), "SYNR to " + address);
    }
  } else {
    let blueprint = await deployUtils.attach("SynCityCoupons");
    for (let address of testnetWallets) {
      await deployUtils.Tx(blueprint.mint(address, 10), "Blueprints to " + address);
    }
  }
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
