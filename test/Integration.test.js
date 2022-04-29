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

describe("#Integration test", function () {
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

  async function initAndDeploy() {
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

    sSynr = await SyntheticSyndicateERC20.deploy(superAdmin.address);
    await sSynr.deployed();

    await sSynr.connect(superAdmin).mint(fundOwner.address, ethers.utils.parseEther("300000"));
    await sSynr.connect(superAdmin).mint(user2.address, ethers.utils.parseEther("200000"));

    pass = await SynCityPasses.deploy(validator.address);
    await pass.deployed();

    await pass.mintToken(fundOwner.address);
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
    await seedPool.initPool(1000, 7 * 24 * 3600, 9800, 1000, 100, 800, 3000, 10);
    await seedPool.updateNftConf(100000, 1500, 500000, 150, 1000);

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

  async function configure() {}

  beforeEach(async function () {
    await initAndDeploy();
  });

  it("should manage the entire flow", async function () {
    const amount = ethers.utils.parseEther("10000");
    const amount2 = ethers.utils.parseEther("20000");
    const amount3 = ethers.utils.parseEther("5000");

    // stake SYNR in the SynrBridge
    let payload = await serializeInput(
      SYNR_STAKE, // SYNR
      365, // 1 year
      amount
    );
    expect(payload).equal("1000000000000000000000036502");

    let payload2 = await serializeInput(
      SYNR_STAKE, // SYNR
      150, // 1 year
      amount2
    );
    expect(payload2).equal("2000000000000000000000015002");

    let payload3 = await serializeInput(
      S_SYNR_SWAP, // sSYNR
      0, // 1 year
      amount3
    );
    expect(payload3).equal("500000000000000000000000001");

    await synr.connect(fundOwner).approve(mainPool.address, ethers.utils.parseEther("35000"));

    expect(
      await synrBridge.connect(fundOwner).wormholeTransfer(
        payload,
        4, // BSC
        bytes32Address(fundOwner.address),
        1
      )
    )
      .emit(synrBridge, "DepositSaved")
      .withArgs(fundOwner.address, 0);

    let tvl = await mainPool.tvl();
    expect(tvl.synrAmount).equal(amount);

    let deposit = await mainPool.getDepositByIndex(fundOwner.address, 0);
    expect(deposit.tokenAmountOrID).equal(amount);
    expect(deposit.tokenType).equal(SYNR_STAKE);
    expect(deposit.otherChain).equal(4);

    const finalPayload = await fromDepositToTransferPayload(deposit);

    await sSynr.connect(user2).approve(mainPool.address, ethers.utils.parseEther("30000"));

    expect(
      synrBridge.connect(user2).wormholeTransfer(
        payload3,
        4, // BSC
        bytes32Address(fundOwner.address),
        1
      )
    ).revertedWith("SynrBridge: only the sender can receive on other chain");

    expect(
      await synrBridge.connect(user2).wormholeTransfer(
        payload3,
        4, // BSC
        bytes32Address(user2.address),
        1
      )
    )
      .emit(synrBridge, "DepositSaved")
      .withArgs(user2.address, 0);

    let deposit3 = await mainPool.getDepositByIndex(user2.address, 0);
    expect(deposit3.tokenAmountOrID).equal(amount3);
    expect(deposit3.tokenType).equal(S_SYNR_SWAP);
    expect(deposit3.otherChain).equal(4);
    const finalPayload3 = await fromDepositToTransferPayload(deposit3);

    expect(
      await synrBridge.connect(fundOwner).wormholeTransfer(
        payload2,
        4, // BSC
        bytes32Address(fundOwner.address),
        2
      )
    )
      .emit(synrBridge, "DepositSaved")
      .withArgs(fundOwner.address, 1);

    tvl = await mainPool.tvl();
    expect(tvl.synrAmount).equal(amount.add(amount2));

    let deposit2 = await mainPool.getDepositByIndex(fundOwner.address, 1);
    expect(deposit2.tokenAmountOrID).equal(amount2);
    expect(deposit2.tokenType).equal(SYNR_STAKE);
    expect(deposit2.otherChain).equal(4);
    const finalPayload2 = await fromDepositToTransferPayload(deposit2);

    expect(await synr.balanceOf(mainPool.address)).equal(amount.add(amount2));

    expect(await seedFactory.mockWormholeCompleteTransfer(fundOwner.address, finalPayload))
      .emit(seedFactory, "DepositSaved")
      .withArgs(fundOwner.address, 0);

    let conf2 = await seedPool.conf();
    let tvl2 = await seedPool.tvl();
    let seedAmount = amount.mul(conf2.stakeFactor).mul(conf2.priceRatio).div(10000);
    expect(tvl2.stakedTokenAmount).equal(seedAmount);

    expect(await seed.balanceOf(fundOwner.address)).equal(0);

    expect(await seedFactory.mockWormholeCompleteTransfer(fundOwner.address, finalPayload2))
      .emit(seedFactory, "DepositSaved")
      .withArgs(fundOwner.address, 1);

    expect(await seed.balanceOf(fundOwner.address)).equal("350076103500761035007");

    expect(await seedFactory.mockWormholeCompleteTransfer(user2.address, finalPayload3))
      .emit(seedFactory, "DepositSaved")
      .withArgs(user2.address, 0);

    conf2 = await seedPool.conf();
    tvl2 = await seedPool.tvl();
    let seedAmount2 = amount2.mul(conf2.stakeFactor).mul(conf2.priceRatio).div(10000);
    let seedAmount3 = amount3.mul(conf2.swapFactor).mul(conf2.priceRatio).div(10000);

    expect(tvl2.stakedTokenAmount).equal(seedAmount.add(seedAmount2).add(seedAmount3));

    await increaseBlockTimestampBy(20 * 24 * 3600);

    let ts = await getTimestamp();
    const untaxedPendingRewards = await seedPool.untaxedPendingRewards(fundOwner.address, ts + 1);

    let boostWeight = await seedPool.boostWeight(fundOwner.address);
    expect(boostWeight).equal(10000);

    await seedPool.connect(fundOwner).collectRewards();
    let seedDeposit = await seedPool.getDepositByIndex(fundOwner.address, 0);
    expect(seedDeposit.lastRewardsAt).equal(await getTimestamp());

    ts = await getTimestamp();
    const untaxedPendingRewards3 = await seedPool.untaxedPendingRewards(user2.address, ts + 1);
    const tax = await seedPool.calculateTaxOnRewards(untaxedPendingRewards3);
    expect(await seed.balanceOf(user2.address)).equal(0);

    await seedPool.connect(user2).collectRewards();
    expect(await seed.balanceOf(user2.address)).equal(untaxedPendingRewards3.sub(tax));

    let payload4 = await serializeInput(
      SYNR_PASS_STAKE_FOR_BOOST, // sSYNR
      0, // 1 year
      9
    );
    expect(payload4).equal("900003");

    // approve the spending of the pass
    await pass.connect(fundOwner).approve(mainPool.address, 9);

    expect(
      await synrBridge.connect(fundOwner).wormholeTransfer(
        payload4,
        4, // BSC
        bytes32Address(fundOwner.address),
        3
      )
    )
      .emit(synrBridge, "DepositSaved")
      .withArgs(fundOwner.address, 2);

    let deposit4 = await mainPool.getDepositByIndex(fundOwner.address, 2);
    const finalPayload4 = await fromDepositToTransferPayload(deposit4);

    expect(await seedFactory.mockWormholeCompleteTransfer(fundOwner.address, finalPayload4))
      .emit(seedFactory, "DepositSaved")
      .withArgs(fundOwner.address, 2);

    boostWeight = await seedPool.boostWeight(fundOwner.address);
    expect(boostWeight).equal(10250);

    await increaseBlockTimestampBy(20 * 24 * 3600);

    ts = await getTimestamp();

    const untaxedPendingRewardsBoosted = await seedPool.untaxedPendingRewards(fundOwner.address, ts + 1);

    // console.log(untaxedPendingRewards.toString())
    // console.log(untaxedPendingRewardsBoosted.toString())

    await increaseBlockTimestampBy(330 * 24 * 3600);

    expect(seedDeposit.unstakedAt).equal(0);
    expect(seedDeposit.tokenAmount).equal(ethers.utils.parseEther("1000000"));
    const seedPayload = await fromDepositToTransferPayload(seedDeposit);

    ts = await getTimestamp();
    // unstake

    expect(await seedFactory.connect(fundOwner).wormholeTransfer(seedPayload, 2, bytes32Address(fundOwner.address), 1))
      .emit(seedFactory, "DepositUnlocked")
      .withArgs(fundOwner.address, 0);

    // unstake SEED from sSYNR

    expect(await seed.balanceOf(user2.address)).equal("129467945205479452054794520");

    await seedPool.connect(user2).unstake(0);

    expect(await seed.balanceOf(user2.address)).equal("134467945205479452054794520");

    seedDeposit = await seedPool.getDepositByIndex(fundOwner.address, 0);
    expect(seedDeposit.tokenAmountOrID).equal(amount);
    expect(seedDeposit.unstakedAt).equal(ts + 1);
    const synrBalanceBefore = await synr.balanceOf(fundOwner.address);

    expect(await synrBridge.mockWormholeCompleteTransfer(fundOwner.address, seedPayload))
      .emit(synrBridge, "DepositUnlocked")
      .withArgs(fundOwner.address, 0);

    const synrBalanceAfter = await synr.balanceOf(fundOwner.address);
    expect(synrBalanceAfter.sub(synrBalanceBefore)).equal(amount);
  });

  it("should verify early unstake", async function () {
    const amount = ethers.utils.parseEther("10000");
    await synr.connect(fundOwner).transferFrom(fundOwner.address, user1.address, amount);

    // stake SYNR in the SynrBridge
    const payload = await serializeInput(
      SYNR_STAKE, // SYNR
      300,
      amount
    );

    expect(payload).equal("1000000000000000000000030002");

    await synr.connect(user1).approve(mainPool.address, ethers.utils.parseEther("10000"));

    await synrBridge.connect(user1).wormholeTransfer(
      payload,
      4, // BSC
      bytes32Address(user1.address),
      1
    );

    let deposit = await mainPool.getDepositByIndex(user1.address, 0);
    expect(deposit.tokenAmountOrID).equal(amount);
    expect(deposit.tokenType).equal(SYNR_STAKE);
    expect(deposit.otherChain).equal(4);

    const finalPayload = await fromDepositToTransferPayload(deposit);

    expect(await synr.balanceOf(mainPool.address)).equal(amount);

    await seedFactory.connect(user1).mockWormholeCompleteTransfer(user1.address, finalPayload);

    await increaseBlockTimestampBy(150 * 24 * 3600);

    expect(await seedPool.canUnstakeWithoutTax(user1.address, 0)).equal(false);

    let seedDeposit = await seedPool.getDepositByIndex(user1.address, 0);
    expect(seedDeposit.unstakedAt).equal(0);
    const seedPayload = await fromDepositToTransferPayload(seedDeposit);

    const synrBalanceBefore = await synr.balanceOf(user1.address);

    // unstake
    await seedFactory.connect(user1).wormholeTransfer(seedPayload, 2, bytes32Address(user1.address), 1);

    const ts = await getTimestamp();
    const tax = await mainPool.calculatePenaltyForEarlyUnstake(ts, await mainPool.getDepositByIndex(user1.address, 0));
    expect(amount.sub(tax)).equal("8000000000000000000000");

    await synrBridge.mockWormholeCompleteTransfer(user1.address, seedPayload);

    const synrBalanceAfter = await synr.balanceOf(user1.address);
    expect(synrBalanceAfter.sub(synrBalanceBefore)).equal(amount.sub(tax));

    expect(await mainPool.penalties()).equal(tax);
    const synrBalanceBeforePenalty = await synr.balanceOf(user2.address);
    await mainPool.withdrawPenalties(tax, user2.address);
    const synrBalanceAfterPenalty = await synr.balanceOf(user2.address);
    expect(await synrBalanceAfterPenalty).equal(synrBalanceBeforePenalty + tax);
  });

  it("should start the process, upgrade the contract and complete the flow", async function () {
    const amount = ethers.utils.parseEther("10000");

    // stake SYNR in the SynrBridge
    const payload = await serializeInput(
      SYNR_STAKE, // SYNR
      365, // 1 year
      amount
    );

    expect(payload).equal("1000000000000000000000036502");

    await synr.connect(fundOwner).approve(mainPool.address, ethers.utils.parseEther("10000"));

    await synrBridge.connect(fundOwner).wormholeTransfer(
      payload,
      4, // BSC
      bytes32Address(fundOwner.address),
      1
    );

    let deposit = await mainPool.getDepositByIndex(fundOwner.address, 0);
    expect(deposit.tokenAmountOrID).equal(amount);
    expect(deposit.tokenType).equal(SYNR_STAKE);
    expect(deposit.otherChain).equal(4);

    const finalPayload = await fromDepositToTransferPayload(deposit);

    expect(await synr.balanceOf(mainPool.address)).equal(amount);

    await seedFactory.connect(fundOwner).mockWormholeCompleteTransfer(fundOwner.address, finalPayload);

    await increaseBlockTimestampBy(366 * 24 * 3600);

    // upgrade contract

    expect(await synrBridge.version()).equal(1);

    synrBridge = await upgrades.upgradeProxy(synrBridge.address, SynrBridgeV2);

    expect(await synrBridge.version()).equal(2);

    let seedDeposit = await seedPool.getDepositByIndex(fundOwner.address, 0);
    expect(seedDeposit.unstakedAt).equal(0);
    const seedPayload = await fromDepositToTransferPayload(seedDeposit);

    const ts = await getTimestamp();
    // unstake
    await seedFactory.connect(fundOwner).wormholeTransfer(seedPayload, 2, bytes32Address(fundOwner.address), 1);
    seedDeposit = await seedPool.getDepositByIndex(fundOwner.address, 0);

    expect(seedDeposit.unstakedAt).greaterThan(ts);

    const synrBalanceBefore = await synr.balanceOf(fundOwner.address);

    await synrBridge.mockWormholeCompleteTransfer(fundOwner.address, seedPayload);
    const synrBalanceAfter = await synr.balanceOf(fundOwner.address);
    expect(synrBalanceAfter.sub(synrBalanceBefore)).equal(amount);
  });
});
