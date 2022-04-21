const {expect, assert} = require("chai");

const {
  initEthers,
  SYNR_STAKE,
  assertThrowsMessage,
  getTimestamp,
  increaseBlockTimestampBy,
  bytes32Address,
  BLUEPRINT_STAKE_FOR_BOOST,
} = require("./helpers");
const {upgrades} = require("hardhat");

// tests to be fixed

function normalize(val, n = 18) {
  return "" + val + "0".repeat(n);
}

// test unit coming soon

describe("#SidePool", function () {
  let WormholeMock, wormhole;
  let SeedToken, seed;
  let coupon;
  let SidePool, sidePool;
  let SynCityCouponsSimplified, blueprint;
  let week = 7 * 24 * 3600;

  let deployer, fundOwner, superAdmin, operator, validator, user1, user2, marketplace, treasury;

  before(async function () {
    initEthers(ethers);
    [deployer, fundOwner, superAdmin, operator, validator, user1, user2, marketplace, treasury] = await ethers.getSigners();
    SeedToken = await ethers.getContractFactory("SeedToken");
    SidePool = await ethers.getContractFactory("SidePoolMock");
    SynCityCouponsSimplified = await ethers.getContractFactory("SynCityCouponsSimplified");
  });

  async function initAndDeploy(initPool) {
    seed = await SeedToken.deploy();
    await seed.deployed();

    blueprint = await SynCityCouponsSimplified.deploy(8000);
    await blueprint.deployed();

    sidePool = await upgrades.deployProxy(SidePool, [seed.address, seed.address, blueprint.address]);
    await sidePool.deployed();

    if (initPool) {
      await sidePool.initPool(1000, week, 9800, 1000, 100, 800, 3000, 10);
      await sidePool.updateNftConf(100000, 1500, 120000, 150, 1000);
    }
  }

  let deposit;

  describe("#initPool", async function () {
    beforeEach(async function () {
      await initAndDeploy();
    });

    it("should revert if already initiated", async function () {
      await sidePool.initPool(1000, week, 9800, 1000, 100, 800, 3000, 10);
      expect(sidePool.initPool(1000, week, 9800, 1000, 100, 1000, 3000, 10)).revertedWith("SidePool: already initiated");
    });

    it("should revert if wrong parameters", async function () {
      await assertThrowsMessage(sidePool.initPool(1000, week, 129800, 1000, 100, 800, 3000, 10), "value out-of-bounds");
      await assertThrowsMessage(sidePool.initPool(1000, 1e12, 9800, 1000, 100, 800, 3000, 10), "value out-of-bounds");
      await assertThrowsMessage(sidePool.initPool(1e10, week, 9800, 1000, 100, 800, 3000, 10), "value out-of-bounds");
      await assertThrowsMessage(sidePool.initPool(1000, week, 9800, 1000, 100, 800, 233000, 10), "value out-of-bounds");
    });
  });

  describe("#getLockupTime", async function () {
    beforeEach(async function () {
      await initAndDeploy(true);
      //
      const amount = ethers.utils.parseEther("9650");
      const lockedFrom = await getTimestamp();
      const lockedUntil = lockedFrom + 3600 * 24 * 180;
      deposit = {
        tokenType: SYNR_STAKE,
        lockedFrom,
        lockedUntil,
        tokenAmountOrID: amount,
        tokenAmount: amount.mul(100),
        unstakedAt: 0,
        mainIndex: 0,
        lastRewardsAt: lockedFrom,
        rewardsFactor: 1000,
      };
    });

    it("should calculate the yield weight", async function () {
      expect(await sidePool.getLockupTime(deposit)).equal(180);
    });
  });

  describe("#yieldWeight", async function () {
    beforeEach(async function () {
      await initAndDeploy(true);
    });

    it("should calculate the yield weight", async function () {
      // 14962 means a weight of 1.4962
      expect(await sidePool.yieldWeight(deposit)).equal(14931);
    });
  });

  describe("#updateConf", async function () {
    beforeEach(async function () {
      await initAndDeploy(true);
    });

    it("should be updated", async function () {
      await sidePool.updateConf(11, 22, 33, 44, 55, 66, 77);
      const updated = await sidePool.conf();
      //console.log(updated)
      expect(updated[3]).equal(11);
      expect(updated[4]).equal(22);
      expect(updated[6]).equal(33);
      expect(updated[7]).equal(44);
      expect(updated[8]).equal(55);
      expect(updated[9]).equal(66);
      expect(updated[11]).equal(77);
    });
  });
  describe("#updateOracle", async function () {
    beforeEach(async function () {
      await initAndDeploy(true);
    });
    it("should update oracle", async function () {
      await sidePool.updateOracle(operator.address);
      expect(await sidePool.oracle()).equal(operator.address);
    });
  });

  describe("#updatePriceRatio", async function () {
    beforeEach(async function () {
      await initAndDeploy(true);
    });
    it("should revert if not oracle", async function () {
      await assertThrowsMessage(sidePool.updatePriceRatio(0), "SidePool: not the oracle");
    });
    it("should update the Price Ratio", async function () {
      const ratio = 11111;
      await sidePool.updateOracle(operator.address);
      await sidePool.connect(operator).updatePriceRatio(ratio);
      const updated = await sidePool.conf();
      //console.log(updated[10])
      expect(updated[10]).equal(ratio);
    });
  });

  describe("#updateNftConf", async function () {
    beforeEach(async function () {
      await initAndDeploy(true);
    });
    it("should update the NFT conf", async function () {
      await sidePool.updateNftConf(11, 22, 33, 44, 55);
      const updated = await sidePool.nftConf();
      //console.log(updated)
      expect(updated[0]).equal(11);
      expect(updated[1]).equal(22);
      expect(updated[2]).equal(33);
      expect(updated[3]).equal(44);
      expect(updated[4]).equal(55);
    });
  });

  describe("#pausePool", async function () {
    beforeEach(async function () {
      await initAndDeploy(true);
    });
    it("should Pause the Pool", async function () {
      await sidePool.pausePool(false);
      let updated = await sidePool.conf();
      expect(updated[12]).equal(1);
      await sidePool.pausePool(true);
      updated = await sidePool.conf();
      expect(updated[12]).equal(2);
      await sidePool.pausePool(false);
      updated = await sidePool.conf();
      expect(updated[12]).equal(1);
    });
  });

  describe("#shouldUpdateRatio", async function () {
    beforeEach(async function () {
      await initAndDeploy(true);
    });

    it("should be updated", async function () {
      await increaseBlockTimestampBy(23 * 24 * 3600);
      expect(await sidePool.shouldUpdateRatio()).equal(true);
    });

    it("should not be updated", async function () {
      await increaseBlockTimestampBy(3 * 24 * 3600);
      expect(await sidePool.shouldUpdateRatio()).equal(false);
    });
  });

  describe("#calculateUntaxedRewards", async function () {
    beforeEach(async function () {
      await initAndDeploy(true);
      const amount = ethers.utils.parseEther("9650");
      const lockedFrom = await getTimestamp();
      const lockedUntil = lockedFrom + 3600 * 24 * 180;
      deposit = {
        tokenType: SYNR_STAKE,
        lockedFrom,
        lockedUntil,
        tokenAmountOrID: amount,
        unstakedAt: 0,
        mainIndex: 0,
        tokenAmount: amount.mul(100),
        lastRewardsAt: lockedFrom,
        rewardsFactor: 1000,
      };
    });

    it("should calculate the rewards", async function () {
      await increaseBlockTimestampBy(21 * 24 * 3600);
      expect(await sidePool.calculateUntaxedRewards(deposit, await getTimestamp())).equal("406570153393152000000000000");
    });
  });

  describe("#updateRatio", async function () {
    beforeEach(async function () {
      await initAndDeploy(true);
    });

    it("should update rewardsFactor", async function () {
      await increaseBlockTimestampBy(23 * 24 * 3600);
      await sidePool.updateRatio();
      const conf = await sidePool.conf();
      expect(conf.rewardsFactor).equal(940);
      expect(conf.lastRatioUpdateAt).equal(await getTimestamp());
      expect(await sidePool.shouldUpdateRatio()).equal(false);
    });

    it("should not update rewardsFactor", async function () {
      await increaseBlockTimestampBy(13 * 24 * 3600);
      await sidePool.updateRatio();
      let conf = await sidePool.conf();
      expect(conf.rewardsFactor).equal(980);
      await sidePool.updateRatio();
      conf = await sidePool.conf();
      expect(conf.rewardsFactor).equal(980);
    });
  });

  describe("#stake", async function () {
    beforeEach(async function () {
      await initAndDeploy(true);
    });

    it("should stake blueprints", async function () {
      let id = 2;
      await blueprint.mint(user1.address, 5);
      await blueprint.connect(user1).approve(sidePool.address, id);

      expect(await sidePool.connect(user1).stake(BLUEPRINT_STAKE_FOR_BOOST, 0, id))
        .emit(sidePool, "DepositSaved")
        .withArgs(user1.address, 0);

      //const lockedUntil = (await getTimestamp());
      let deposit = await sidePool.getDepositByIndex(user1.address, 0);
      expect(deposit.tokenAmountOrID).equal(id);
      expect(deposit.tokenType).equal(BLUEPRINT_STAKE_FOR_BOOST);
      //expect(deposit.lockedUntil).equal(lockedUntil);
    });
  });
});
