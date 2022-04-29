const fs = require("fs-extra");
const path = require("path");
const {expect, assert} = require("chai");

const {fromDepositToTransferPayload, serializeInput} = require("../scripts/lib/PayloadUtils");

const {
  initEthers,
  assertThrowsMessage,
  getTimestamp,
  increaseBlockTimestampBy,
  bytes32Address,
  S_SYNR_SWAP,
  SYNR_STAKE,
  SYNR_PASS_STAKE_FOR_BOOST,
  SYNR_PASS_STAKE_FOR_SEEDS,
  BLUEPRINT_STAKE_FOR_BOOST,
} = require("./helpers");
const {upgrades} = require("hardhat");

// tests to be fixed

function normalize(val, n = 18) {
  return "" + val + "0".repeat(n);
}

describe("#Params Calculator", function () {
  let WormholeMock, wormhole;
  let SyndicateERC20, synr;
  let SyntheticSyndicateERC20, sSynr;
  let SynrBridge, synrBridge;
  let MainPool, mainPool;
  let SynrBridgeV2;
  let SeedToken, seed;
  let SynCityPasses, pass;
  let SeedFactory, seedFactory;
  let SeedPool, seedPool;
  let SynCityCouponsSimplified, blueprint;

  let deployer, fundOwner, superAdmin, operator, validator, user1, user2, user3, treasury;

  before(async function () {
    initEthers(ethers);
    [deployer, fundOwner, superAdmin, operator, validator, user1, user2, user3, treasury] = await ethers.getSigners();
    SyndicateERC20 = await ethers.getContractFactory("SyndicateERC20");
    SyntheticSyndicateERC20 = await ethers.getContractFactory("SyntheticSyndicateERC20");
    SynrBridge = await ethers.getContractFactory("SynrBridgeMock");
    SynrBridgeV2 = await ethers.getContractFactory("SynrBridgeV2Mock");
    SeedFactory = await ethers.getContractFactory("SeedFactoryMock");
    SeedPool = await ethers.getContractFactory("SeedPool");
    MainPool = await ethers.getContractFactory("MainPool");
    SeedToken = await ethers.getContractFactory("SeedToken");
    WormholeMock = await ethers.getContractFactory("WormholeMock");
    SynCityPasses = await ethers.getContractFactory("SynCityPassesMock");
    SynCityCouponsSimplified = await ethers.getContractFactory("SynCityCouponsSimplified");
  });

  async function initAndDeploy(
    stakeFactor = 1000,
    swapFactor = 10000,
    synrEquivalent = 100000,
    sPBoostFactor = 1500,
    sPBoostLimit = 500000
  ) {
    const maxTotalSupply = 10000000000; // 10 billions
    synr = await SyndicateERC20.deploy(fundOwner.address, maxTotalSupply, superAdmin.address);
    await synr.deployed();
    let features =
      (await synr.FEATURE_TRANSFERS_ON_BEHALF()) +
      (await synr.FEATURE_TRANSFERS()) +
      (await synr.FEATURE_UNSAFE_TRANSFERS()) +
      (await synr.FEATURE_DELEGATIONS()) +
      (await synr.FEATURE_DELEGATIONS_ON_BEHALF());
    await synr.updateFeatures(features);

    synr.connect(fundOwner).transfer(user1.address, ethers.utils.parseEther("1000000000"));
    synr.connect(fundOwner).transfer(user2.address, ethers.utils.parseEther("1000000000"));

    sSynr = await SyntheticSyndicateERC20.deploy(superAdmin.address);
    await sSynr.deployed();

    await sSynr.connect(superAdmin).mint(user1.address, ethers.utils.parseEther("1000000000"));
    await sSynr.connect(superAdmin).mint(user2.address, ethers.utils.parseEther("1000000000"));

    pass = await SynCityPasses.deploy(validator.address);
    await pass.deployed();

    await pass.mintToken(user1.address);
    await pass.mintToken(user1.address);
    await pass.mintToken(user2.address);
    await pass.mintToken(user2.address);

    mainPool = await upgrades.deployProxy(MainPool, [synr.address, sSynr.address, pass.address]);
    await mainPool.deployed();

    synrBridge = await upgrades.deployProxy(SynrBridge, [mainPool.address]);
    await synrBridge.deployed();

    await sSynr.updateRole(mainPool.address, await sSynr.ROLE_WHITE_LISTED_RECEIVER());
    await mainPool.setFactory(synrBridge.address);

    seed = await SeedToken.deploy();
    await seed.deployed();

    blueprint = await SynCityCouponsSimplified.deploy(8000);
    await blueprint.deployed();

    await blueprint.mint(user1.address, 2);
    await blueprint.mint(user3.address, 1);

    seedPool = await upgrades.deployProxy(SeedPool, [seed.address, blueprint.address]);
    await seedPool.deployed();
    await seedPool.initPool(1000, 7 * 24 * 3600, 9800, swapFactor, stakeFactor, 800, 3000, 10);
    await seedPool.updateNftConf(synrEquivalent, sPBoostFactor, sPBoostLimit, 150, 1000);

    seedFactory = await upgrades.deployProxy(SeedFactory, [seedPool.address]);
    await seedFactory.deployed();

    await seedPool.setFactory(seedFactory.address);
    await seed.grantRole(await seed.MINTER_ROLE(), seedPool.address);

    wormhole = await WormholeMock.deploy();
    await synrBridge.wormholeInit(2, wormhole.address);
    await wormhole.deployed();

    await synrBridge.wormholeRegisterContract(4, bytes32Address(seedFactory.address));
    await mainPool.initPool(7, 4000);

    await seedFactory.wormholeInit(4, wormhole.address);
    await seedFactory.wormholeRegisterContract(2, bytes32Address(synrBridge.address));
  }

  it.skip("should verify possible combination", async function () {
    const params = [
      [650, 50000],
      [550, 45000],
      [600, 50000],
      [680, 48000],
      [750, 60000],
      [700, 50000],
      [720, 49000],
      [1, 84],
    ];

    let report = [
      [
        "stakeFactor",
        "swapFactor",
        "SYNR/sSYNR amount",
        "SEED after staking SYNR",
        "SEED after swapping sSYNR",
        "Final SEED for SYNR",
        "Final SEED for sSYNR",
        "Ratio",
      ],
    ];

    for (let i = 0; i < params.length; i++) {
      const tokenAmount = "100000";
      const amount = ethers.utils.parseEther(tokenAmount);
      let [stakeFactor, swapFactor] = params[i];

      const row = [stakeFactor, swapFactor, tokenAmount];

      await initAndDeploy(stakeFactor, swapFactor);

      // approve SYNR spend
      await synr.connect(user1).approve(mainPool.address, amount);

      // console.log(amount.toString());

      let payload = await serializeInput(SYNR_STAKE, 365, amount);
      await synrBridge.connect(user1).wormholeTransfer(payload, 4, bytes32Address(user1.address), 1);

      // approve sSYNR spend
      await sSynr.connect(user2).approve(mainPool.address, amount);
      let payload2 = await serializeInput(S_SYNR_SWAP, 0, amount);
      await synrBridge.connect(user2).wormholeTransfer(payload2, 4, bytes32Address(user2.address), 1);

      let deposit = await mainPool.getDepositByIndex(user1.address, 0);
      let finalPayload = await fromDepositToTransferPayload(deposit);

      await seedFactory.mockWormholeCompleteTransfer(user1.address, finalPayload);

      deposit = await mainPool.getDepositByIndex(user2.address, 0);
      finalPayload = await fromDepositToTransferPayload(deposit);

      await seedFactory.mockWormholeCompleteTransfer(user2.address, finalPayload);

      await increaseBlockTimestampBy(366 * 24 * 3600);

      // unstake SEED and SYNR
      let seedDeposit = await seedPool.getDepositByIndex(user1.address, 0);
      let seedPayload = await fromDepositToTransferPayload(seedDeposit);

      let stakedSeedFromSYNR = ethers.utils.formatEther(seedDeposit.tokenAmount.toString()).toString().split(".")[0];
      row.push(stakedSeedFromSYNR);

      let seedDeposit2 = await seedPool.getDepositByIndex(user2.address, 0);

      let stakedSeedFromSSYNR = ethers.utils.formatEther(seedDeposit2.tokenAmount.toString()).toString().split(".")[0];
      row.push(stakedSeedFromSSYNR);

      await seedFactory.connect(user1).wormholeTransfer(seedPayload, 2, bytes32Address(user1.address), 1);

      let seedFromSYNR = ethers.utils
        .formatEther((await seed.balanceOf(user1.address)).toString())
        .toString()
        .split(".")[0];

      row.push(seedFromSYNR);

      // unstake SEED from sSYNR

      await seedPool.connect(user2).unstake(0);
      let seedFromSSYNR = ethers.utils
        .formatEther((await seed.balanceOf(user2.address)).toString())
        .toString()
        .split(".")[0];
      row.push(seedFromSSYNR);
      row.push(parseInt(seedFromSYNR) / parseInt(seedFromSSYNR));

      report.push(row);

      if (!i) {
        console.info("APY:", parseInt(seedFromSYNR) / parseInt(stakedSeedFromSYNR));
      }
    }
    await fs.ensureDir(path.resolve(__dirname, "../tmp"));
    report.sort((a, b) => {
      a = a[7];
      b = b[7];
      return a > b ? 1 : a < b ? -1 : 0;
    });
    report = report.map((e) => e.join("\t")).join("\n");
    await fs.writeFile(path.resolve(__dirname, "../tmp/report.csv"), report);
    console.info(report);

    console.info("Report saved in", path.resolve(__dirname, "../tmp/report.csv"));
  });
});
