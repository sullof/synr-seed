const ethers = require("ethers");

const S_SYNR_SWAP = 1;
const SYNR_STAKE = 2;
const SYNR_PASS_STAKE_FOR_BOOST = 3;
const SYNR_PASS_STAKE_FOR_SEEDS = 4;
const BLUEPRINT_STAKE_FOR_BOOST = 5;
const BLUEPRINT_STAKE_FOR_SEEDS = 6;
const SEED_SWAP = 7;

const BN = ethers.BigNumber.from;
async function BNMulBy(param, num = 1, repeat = 0) {
  if (repeat) {
    return BN(param.toString()).mul(BN(num + "0".repeat(repeat)));
  }
  return BN(param.toString()).mul(num);
}

const DAY = 24 * 3600;
const WEEK = DAY * 7;
const YEAR = 365 * DAY;

const PayloadUtils = {
  async fromMainDepositToTransferPayload(deposit) {
    return BN(deposit.tokenType)
      .add(await BNMulBy(deposit.lockedFrom, 100))
      .add(await BNMulBy(deposit.lockedUntil, 1, 12))
      .add(await BNMulBy(deposit.mainIndex, 1, 22))
      .add(await BNMulBy(deposit.tokenAmountOrID, 1, 27));
  },

  async fromSideDepositToTransferPayload(deposit) {
    return BN(deposit.tokenType)
      .add(await BNMulBy(deposit.lockedFrom, 100))
      .add(await BNMulBy(deposit.lockedUntil, 1, 12))
      .add(await BNMulBy(deposit.mainIndex, 1, 22))
      .add(await BNMulBy(deposit.tokenType < SYNR_PASS_STAKE_FOR_BOOST ? deposit.stakedAmount : deposit.tokenID, 1, 27));
  },

  async serializeInput(tokenType, lockupTime, tokenAmountOrID) {
    return BN(tokenType)
      .add(await BNMulBy(lockupTime, 100))
      .add(await BNMulBy(tokenAmountOrID, 1, 5));
  },

  calculateUntaxedRewards(deposit, timestamp) {
    if (deposit.tokenAmount === 0 || deposit.lastRewardsAt > deposit.lockedUntil) {
      return 0;
    }
    let when = deposit.lockedUntil > timestamp ? timestamp : deposit.lockedUntil;
    let lockupTime = BN(deposit.lockedUntil.toString()).sub(deposit.lockedFrom);
    let yieldWeight = BN("10000").add(lockupTime.mul(10000).div(365).div(DAY));
    return ethers.BigNumber.from(deposit.tokenAmount.toString())
      .mul(deposit.rewardsFactor)
      .mul(BN(when).sub(deposit.lastRewardsAt))
      .div(365 * DAY)
      .mul(yieldWeight)
      .div(10000);
  },
};

module.exports = PayloadUtils;
