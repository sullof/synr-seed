require("dotenv").config();
const hre = require("hardhat");
const ethers = hre.ethers;

const DeployUtils = require("./lib/DeployUtils");
const testnetWallets = require("./testnetWallets");
let deployUtils;

async function main() {
  deployUtils = new DeployUtils(ethers);
  const [deployer] = await ethers.getSigners();
  // const weed = await deployUtils.deployProxy("WeedTokenMock");
  const weed = await deployUtils.attach("WeedTokenMock");
  // await deployUtils.Tx(weed.setMinter(deployer.address, true), "Set deployer as minter");
  //
  // for (let address of testnetWallets) {
  //   await deployUtils.Tx(
  //     weed.mint(address, ethers.utils.parseEther("200000"), {
  //       gasLimit: 120000,
  //     }),
  //     "WEED to " + address
  //   );
  // }

  let address = "0xF97873847BEe001E37E009ebF5fEFB15A5deb5c3";
  await deployUtils.Tx(
    weed.mint(address, ethers.utils.parseEther("200000000"), {
      gasLimit: 1000000,
    }),
    "WEED to " + address
  );
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
