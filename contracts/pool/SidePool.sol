// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

// Author: Francesco Sullo <francesco@sullo.co>
// (c) 2022+ SuperPower Labs Inc.

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../token/TokenReceiver.sol";
import "../utils/PayloadUtils.sol";
import "../interfaces/ISidePool.sol";
import "../token/SideToken.sol";
import "../token/SynCityCouponsSimplified.sol";

import "hardhat/console.sol";

contract SidePool is PayloadUtils, ISidePool, TokenReceiver, Initializable, OwnableUpgradeable, UUPSUpgradeable {
  using SafeMathUpgradeable for uint256;
  using AddressUpgradeable for address;

  // users and deposits
  mapping(address => User) public users;
  Conf public conf;
  NftConf public nftConf;

  SideToken public rewardsToken;
  SideToken public stakedToken;
  SynCityCouponsSimplified public blueprint;

  uint256 public penalties;
  uint256 public taxes;
  address public oracle;
  address public factory;

  TVL public tvl;

  //  /// @custom:oz-upgrades-unsafe-allow constructor
  //  constructor() initializer {}

  // solhint-disable-next-line
  function __SidePool_init(
    address stakedToken_,
    address rewardsToken_,
    address blueprint_
  ) public initializer {
    __Ownable_init();
    require(stakedToken_.isContract(), "SidePool: stakedToken not a contract");
    require(rewardsToken_.isContract(), "SidePool: rewardsToken not a contract");
    require(blueprint_.isContract(), "SidePooL: Blueprint not a contract");
    // in SeedFarm, stakedToken and rewardsToken are same token, SEED
    stakedToken = SideToken(stakedToken_);
    rewardsToken = SideToken(rewardsToken_);
    blueprint = SynCityCouponsSimplified(blueprint_);
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function initPool(
    uint32 rewardsFactor_,
    uint32 decayInterval_,
    uint16 decayFactor_,
    uint16 swapFactor_,
    uint16 stakeFactor_,
    uint16 taxPoints_,
    uint16 burnRatio_,
    uint8 coolDownDays_
  ) external override onlyOwner {
    require(conf.maximumLockupTime == 0, "SidePool: already initiated");
    conf = Conf({
      rewardsFactor: rewardsFactor_,
      decayInterval: decayInterval_,
      decayFactor: decayFactor_,
      maximumLockupTime: 365,
      poolInitAt: uint32(block.timestamp),
      lastRatioUpdateAt: uint32(block.timestamp),
      swapFactor: swapFactor_,
      stakeFactor: stakeFactor_,
      taxPoints: taxPoints_,
      burnRatio: burnRatio_,
      priceRatio: 10000,
      coolDownDays: coolDownDays_,
      status: 1
    });
  }

  // put to zero any parameter that remains the same
  function updateConf(
    uint32 decayInterval_,
    uint16 decayFactor_,
    uint16 swapFactor_,
    uint16 stakeFactor_,
    uint16 taxPoints_,
    uint16 burnRatio_,
    uint8 coolDownDays_
  ) external override onlyOwner {
    require(conf.status == 1, "SidePool: not active");
    if (decayInterval_ > 0) {
      conf.decayInterval = decayInterval_;
    }
    if (decayFactor_ > 0) {
      conf.decayFactor = decayFactor_;
    }
    if (swapFactor_ > 0) {
      conf.swapFactor = swapFactor_;
    }
    if (stakeFactor_ > 0) {
      conf.stakeFactor = stakeFactor_;
    }
    if (taxPoints_ > 0) {
      conf.taxPoints = taxPoints_;
    }
    if (burnRatio_ > 0) {
      conf.burnRatio = burnRatio_;
    }
    if (coolDownDays_ > 0) {
      conf.coolDownDays = coolDownDays_;
    }
  }

  // put to zero any parameter that remains the same
  function updatePriceRatio(uint16 priceRatio_) external override {
    require(conf.status == 1, "SidePool: not active");
    require(oracle != address(0) && _msgSender() == oracle, "SidePool: not the oracle");
    if (priceRatio_ > 0) {
      conf.priceRatio = priceRatio_;
    }
  }

  // put to zero any parameter that remains the same
  function updateOracle(address oracle_) external override onlyOwner {
    require(oracle_ != address(0), "SidePool: not a valid address");
    oracle = oracle_;
  }

  // put to zero any parameter that remains the same
  function updateNftConf(
    uint32 synrEquivalent_,
    uint16 sPBoostFactor_,
    uint32 sPBoostLimit_,
    uint16 bPBoostFactor_,
    uint32 bPBoostLimit_
  ) external override onlyOwner {
    require(conf.status == 1, "SidePool: not active");
    if (synrEquivalent_ > 0) {
      nftConf.synrEquivalent = synrEquivalent_;
    }
    if (sPBoostFactor_ > 0) {
      nftConf.sPBoostFactor = sPBoostFactor_;
    }
    if (bPBoostFactor_ > 0) {
      nftConf.bPBoostFactor = bPBoostFactor_;
    }
    if (sPBoostLimit_ > 0) {
      nftConf.sPBoostLimit = sPBoostLimit_;
    }
    if (bPBoostLimit_ > 0) {
      nftConf.bPBoostLimit = bPBoostLimit_;
    }
  }

  function pausePool(bool paused) external onlyOwner {
    conf.status = paused ? 2 : 1;
  }

  function version() external pure virtual override returns (uint256) {
    return 1;
  }

  function _updateLastRatioUpdateAt() internal {
    conf.lastRatioUpdateAt = uint32(block.timestamp);
  }

  function shouldUpdateRatio() public view override returns (bool) {
    return
      block.timestamp.sub(conf.poolInitAt).div(conf.decayInterval) >
      uint256(conf.lastRatioUpdateAt).sub(conf.poolInitAt).div(conf.decayInterval);
  }

  /**
   * @param deposit The deposit
   * @return the time it will be locked
   */
  function getLockupTime(Deposit memory deposit) public pure override returns (uint256) {
    return uint256(deposit.lockedUntil).sub(deposit.lockedFrom).div(1 days);
  }

  function updateRatio() public override {
    if (shouldUpdateRatio()) {
      uint256 count = block.timestamp.sub(conf.poolInitAt).div(conf.decayInterval) -
        uint256(conf.lastRatioUpdateAt).sub(conf.poolInitAt).div(conf.decayInterval);
      uint256 ratio = uint256(conf.rewardsFactor);
      for (uint256 i = 0; i < count; i++) {
        ratio = ratio.mul(conf.decayFactor).div(10000);
      }
      conf.rewardsFactor = uint32(ratio);
      conf.lastRatioUpdateAt = uint32(block.timestamp);
    }
  }

  /**
   * @param deposit The deposit
   * @return the weighted yield
   */
  function yieldWeight(Deposit memory deposit) public view override returns (uint256) {
    return uint256(10000).add(getLockupTime(deposit).mul(10000).div(conf.maximumLockupTime));
  }

  /**
   * @param deposit The deposit
   * @param timestamp Current time of the stake
   * @return the Amount of untaxed reward
   */
  function calculateUntaxedRewards(Deposit memory deposit, uint256 timestamp) public view override returns (uint256) {
    if (deposit.tokenAmount == 0) {
      return 0;
    }
    return
      multiplyByRewardablePeriod(
        uint256(deposit.tokenAmount).mul(deposit.rewardsFactor).mul(yieldWeight(deposit)).div(10000),
        deposit,
        timestamp
      );
  }

  function multiplyByRewardablePeriod(
    uint256 input,
    Deposit memory deposit,
    uint256 timestamp
  ) public view returns (uint256) {
    uint256 lockedUntil = uint256(deposit.lockedUntil);
    if (uint256(deposit.lastRewardsAt) > lockedUntil) {
      return 0;
    }
    uint256 when = lockedUntil > timestamp ? timestamp : lockedUntil;
    return input.mul(when.sub(deposit.lastRewardsAt)).div(365 days);
  }

  /**
   * @notice Calculates the tax for claiming reward
   * @param rewards The rewards of the stake
   */
  function calculateTaxOnRewards(uint256 rewards) public view override returns (uint256) {
    return rewards.mul(conf.taxPoints).div(10000);
  }

  function passForBoostAmount(address user) public view override returns (uint256) {
    uint256 passAmount;
    for (uint256 i = 0; i < users[user].deposits.length; i++) {
      if (users[user].deposits[i].tokenType == SYNR_PASS_STAKE_FOR_BOOST && users[user].deposits[i].unstakedAt == 0) {
        passAmount++;
      }
    }
    return passAmount;
  }

  /**
   * @param user_ address of the owner of the token being boosted
   * @return the amount being boost
   */
  function boostWeight(address user_) public view override returns (uint256) {
    User storage user = users[user_];
    uint256 baseAmount = uint256(user.tokenAmount);
    uint256 boost = 10000;
    if (baseAmount == 0) {
      return boost;
    }
    uint256 boostedAmount = baseAmount;
    uint256 limit;
    uint256 passAmount = passForBoostAmount(user_);
    if (passAmount > 0) {
      // if a SYNR Pass can boost 15000 SYNR (i.e., nftConf.sPBoostLimit)
      // there is a potential limit that depends on how many pass you staked
      limit = uint256(passAmount).mul(nftConf.sPBoostLimit).mul(1e18);
      if (limit < baseAmount) {
        baseAmount = limit;
      }
      boostedAmount += baseAmount.mul(uint256(passAmount).mul(nftConf.sPBoostFactor)).div(10000);
    }
    baseAmount = uint256(user.tokenAmount);
    if (user.blueprintsAmount > 0) {
      limit = uint256(user.blueprintsAmount).mul(nftConf.bPBoostLimit).mul(1e18);
      if (limit < boostedAmount) {
        baseAmount = limit;
      }
      boostedAmount += baseAmount.mul(uint256(user.blueprintsAmount).mul(nftConf.bPBoostFactor)).div(10000);
    }
    return boost.mul(boostedAmount).div(user.tokenAmount);
  }

  function collectRewards() public override {
    _collectRewards(_msgSender());
  }

  /**
   * @notice The reward is collected and the tax is substracted
   * @param user_ The user collecting the reward
   */
  function _collectRewards(address user_) internal {
    User storage user = users[user_];
    uint256 rewards;
    for (uint256 i = 0; i < user.deposits.length; i++) {
      rewards += calculateUntaxedRewards(user.deposits[i], block.timestamp);
      user.deposits[i].lastRewardsAt = uint32(block.timestamp);
    }
    if (rewards > 0) {
      rewards = rewards.mul(boostWeight(user_)).div(10000);
      uint256 tax = calculateTaxOnRewards(rewards);
      rewardsToken.mint(user_, rewards.sub(tax));
      rewardsToken.mint(address(this), tax);
      taxes += tax;
      emit RewardsCollected(user_, rewards.sub(tax));
    }
  }

  /**
   * @param user_ The user collecting the reward
   * @param timestamp Current time of the stake
   * @return the pending rewards that have yet to be taxed
   */
  function untaxedPendingRewards(address user_, uint256 timestamp) external view override returns (uint256) {
    User storage user = users[user_];
    uint256 rewards;
    for (uint256 i = 0; i < user.deposits.length; i++) {
      rewards += calculateUntaxedRewards(user.deposits[i], timestamp);
    }
    if (rewards > 0) {
      rewards = rewards.mul(boostWeight(user_)).div(10000);
    }
    return rewards;
  }

  /**
   * @notice Searches for deposit from the user and its index
   * @param user address of user who made deposit being searched
   * @param index index of the deposit being searched
   * @return the deposit
   */
  function getDepositByIndex(address user, uint256 index) public view override returns (Deposit memory) {
    require(users[user].deposits[index].tokenAmountOrID > 0, "SidePool: deposit not found");
    return users[user].deposits[index];
  }

  /**
   * @param user address of user
   * @return the ammount of deposits a user has made
   */
  function getDepositsLength(address user) public view override returns (uint256) {
    return users[user].deposits.length;
  }

  function _updateTvl(
    uint256 tokenType,
    uint256 tokenAmount,
    bool increase
  ) internal {
    if (increase) {
      if (
        tokenType == SEED_SWAP || tokenType == S_SYNR_SWAP || tokenType == SYNR_STAKE || tokenType == SYNR_PASS_STAKE_FOR_SEEDS
      ) {
        tvl.stakedTokenAmount += uint96(tokenAmount);
      } else if (tokenType == BLUEPRINT_STAKE_FOR_BOOST) {
        tvl.blueprintAmount++;
      }
    } else {
      if (tokenType == SEED_SWAP) {
        tvl.stakedTokenAmount = uint96(uint256(tvl.stakedTokenAmount).sub(tokenAmount));
      } else if (tokenType == BLUEPRINT_STAKE_FOR_BOOST) {
        tvl.blueprintAmount--;
      }
    }
  }

  /**
   * @notice stakes if the pool is active
   * @param user_ address of user being updated
   * @param tokenType identifies the type of transaction being made
   * @param lockedFrom timestamp when locked
   * @param lockedUntil timestamp when can unstake without penalty
   * @param tokenAmountOrID ammount of tokens being staked, in the case where a SYNR Pass is being staked, it identified its ID
   * @param mainIndex index of deposit being updated
   */
  function _stake(
    address user_,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 mainIndex,
    uint256 tokenAmountOrID
  ) internal virtual {
    require(conf.status == 1, "SidePool: not initiated or paused");
    (, bool exists) = getDepositIndexByMainIndex(user_, mainIndex);
    require(!exists, "SidePool: payload already used");
    updateRatio();
    _collectRewards(user_);
    uint256 tokenAmount;
    if (tokenType == S_SYNR_SWAP) {
      tokenAmount = tokenAmountOrID.mul(conf.swapFactor).mul(conf.priceRatio).div(10000);
      stakedToken.mint(address(this), tokenAmount);
    } else if (tokenType == SYNR_STAKE) {
      tokenAmount = tokenAmountOrID.mul(conf.stakeFactor).mul(conf.priceRatio).div(10000);
      stakedToken.mint(address(this), tokenAmount);
    } else if (tokenType == SYNR_PASS_STAKE_FOR_BOOST) {
      users[user_].passAmount++;
    } else if (tokenType == SYNR_PASS_STAKE_FOR_SEEDS) {
      tokenAmount = uint256(nftConf.synrEquivalent).mul(conf.stakeFactor).mul(conf.priceRatio).div(10000);
      stakedToken.mint(address(this), tokenAmount);
    } else if (tokenType == BLUEPRINT_STAKE_FOR_BOOST) {
      users[user_].blueprintsAmount++;
      // SidePool must be approve to spend blueprints
      blueprint.safeTransferFrom(user_, address(this), tokenAmountOrID);
    } else if (tokenType == SEED_SWAP) {
      tokenAmount = tokenAmountOrID;
      // SidePool must be approve to spend SEED
      stakedToken.transferFrom(user_, address(this), tokenAmount);
      taxes += tokenAmount.sub(tokenAmount.mul(conf.burnRatio).div(10000));
      stakedToken.burn(tokenAmount.mul(conf.burnRatio).div(10000));
    } else {
      revert("SidePool: invalid tokenType");
    }
    users[user_].tokenAmount = uint96(uint256(users[user_].tokenAmount).add(tokenAmount));
    _updateTvl(tokenType, tokenAmount, true);
    // add deposit
    if (tokenType == S_SYNR_SWAP || tokenType == SEED_SWAP) {
      lockedUntil = lockedFrom + uint256(conf.coolDownDays).mul(1 days);
    }
    uint256 index = users[user_].deposits.length;
    Deposit memory deposit = Deposit({
      tokenType: uint8(tokenType),
      lockedFrom: uint32(lockedFrom),
      lockedUntil: uint32(lockedUntil),
      tokenAmountOrID: uint96(tokenAmountOrID),
      unstakedAt: 0,
      mainIndex: uint16(mainIndex),
      tokenAmount: uint128(tokenAmount),
      lastRewardsAt: uint32(lockedFrom),
      rewardsFactor: conf.rewardsFactor
    });
    users[user_].deposits.push(deposit);
    emit DepositSaved(user_, uint16(index));
  }

  /**
   * @notice gets Percentage Vested at a certain timestamp
   * @param when timestamp where percentage will be calculated
   * @param lockedFrom timestamp when locked
   * @param lockedUntil timestamp when can unstake without penalty
   * @return the percentage vested
   */
  function getVestedPercentage(
    uint256 when,
    uint256 lockedFrom,
    uint256 lockedUntil
  ) public pure override returns (uint256) {
    if (lockedUntil == 0) {
      return 10000;
    }
    uint256 lockupTime = lockedUntil.sub(lockedFrom);
    if (lockupTime == 0) {
      return 10000;
    }
    uint256 vestedTime = when.sub(lockedFrom);
    // 300 > 3%
    return vestedTime.mul(10000).div(lockupTime);
  }

  /**
   * @notice Only unstakes if the token is SSYNR
   * @param depositIndex index of deposit that wishes to be unstake
   */
  function unstakeIfSSynr(uint256 depositIndex) external override {
    Deposit storage deposit = users[_msgSender()].deposits[depositIndex];
    require(deposit.tokenType == S_SYNR_SWAP, "SidePool: not a sSYNR > SEED swap");
    _collectRewards(_msgSender());
    if (deposit.lockedUntil > block.timestamp) {
      uint256 vestedPercentage = getVestedPercentage(block.timestamp, deposit.lockedFrom, deposit.lockedUntil);
      uint256 unstakedAmount = uint256(deposit.tokenAmount).mul(vestedPercentage).div(10000);
      penalties += uint256(deposit.tokenAmount).sub(unstakedAmount);
      stakedToken.transfer(_msgSender(), unstakedAmount);
    } else {
      stakedToken.transfer(_msgSender(), uint256(deposit.tokenAmount));
    }
    deposit.unstakedAt = uint32(block.timestamp);
  }

  //  function

  /**
   * @param user address of which trying to unstake
   * @param mainIndex the main index of the deposit
   */
  function canUnstakeWithoutTax(address user, uint256 mainIndex) external view override returns (bool) {
    Deposit memory deposit = users[user].deposits[mainIndex];
    return deposit.lockedUntil > 0 && block.timestamp > uint256(deposit.lockedUntil);
  }

  /**
   * @notice Searches for deposit from the user and its index
   * @param user address of user who made deposit being searched
   * @param mainIndex index of the deposit being searched
   * @return the deposit
   */
  function getDepositIndexByMainIndex(address user, uint256 mainIndex) public view override returns (uint256, bool) {
    for (uint256 i; i < users[user].deposits.length; i++) {
      if (uint256(users[user].deposits[i].mainIndex) == mainIndex && users[user].deposits[i].lockedFrom > 0) {
        return (i, true);
      }
    }
    return (0, false);
  }

  /**
   * @notice unstakes a deposit, calculates penalty for early unstake
   * @param tokenType identifies the type of transaction being made
   * @param lockedFrom timestamp when locked
   * @param lockedUntil timestamp when can unstake without penalty
   * @param mainIndex index of deposit
   * @param tokenAmountOrID ammount of tokens being staked, in the case where a SYNR Pass is being staked, it identified its ID
   */
  function _unstake(
    address user_,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 mainIndex,
    uint256 tokenAmountOrID
  ) internal virtual {
    if (tokenType == SYNR_PASS_STAKE_FOR_SEEDS) {
      require(lockedUntil < block.timestamp, "SidePool: SYNR Pass used as SYNR cannot be early unstaked");
    }
    _collectRewards(user_);
    (uint256 index, bool exists) = getDepositIndexByMainIndex(user_, mainIndex);
    require(exists, "SidePool: deposit not found");
    Deposit storage deposit = users[user_].deposits[index];
    require(
      uint256(deposit.tokenType) == tokenType &&
        uint256(deposit.lockedFrom) == lockedFrom &&
        uint256(deposit.lockedUntil) == lockedUntil &&
        uint256(deposit.tokenAmountOrID) == tokenAmountOrID,
      "SidePool: inconsistent deposit"
    );
    if (tokenType == SYNR_STAKE || tokenType == SEED_SWAP || tokenType == S_SYNR_SWAP) {
      uint256 vestedPercentage = getVestedPercentage(
        block.timestamp,
        uint256(deposit.lockedFrom),
        uint256(deposit.lockedUntil)
      );
      uint256 unstakedAmount;
      if (vestedPercentage < 10000) {
        unstakedAmount = uint256(deposit.tokenAmount).mul(vestedPercentage).div(10000);
        penalties += uint256(deposit.tokenAmount).sub(unstakedAmount);
      } else {
        unstakedAmount = uint256(deposit.tokenAmount);
      }
      stakedToken.transfer(user_, unstakedAmount);
    } else if (tokenType == SYNR_PASS_STAKE_FOR_SEEDS) {
      stakedToken.transfer(user_, deposit.tokenAmount);
    } else if (tokenType == SYNR_PASS_STAKE_FOR_BOOST) {
      users[user_].passAmount--;
    } else if (deposit.tokenType == BLUEPRINT_STAKE_FOR_BOOST) {
      users[user_].blueprintsAmount--;
      blueprint.safeTransferFrom(address(this), user_, uint256(deposit.tokenAmountOrID));
    } else {
      revert("SidePool: invalid tokenType");
    }
    _updateTvl(tokenType, tokenAmountOrID, false);
    deposit.unstakedAt = uint32(block.timestamp);
    emit DepositUnlocked(user_, uint16(index));
  }

  /**
   * @notice Withdraws SYNR that has been collected as tax for unstaking early
   * @param amount amount of ssynr to be withdrawn
   * @param beneficiary address to which the withdrawl will go to
   * @param what what is available
   */
  function withdrawPenaltiesOrTaxes(
    uint256 amount,
    address beneficiary,
    uint256 what
  ) external override onlyOwner {
    uint256 available = what == 1 ? penalties : taxes;
    require(amount <= available, "SidePool: amount not available");
    if (amount == 0) {
      amount = available;
    }
    if (what == 1) {
      penalties -= amount;
      stakedToken.transfer(beneficiary, amount);
    } else {
      taxes -= amount;
      rewardsToken.transfer(beneficiary, amount);
    }
  }

  // In SeedFarm you can stake directly only blueprints
  // Must be overridden in FarmingPool
  function stake(
    uint256 tokenType,
    // solhint-disable-next-line
    uint256 lockupTime,
    uint256 tokenAmountOrID
  ) external virtual override {
    // mainIndex = type(uint16).max means no meanIndex
    require(tokenType == BLUEPRINT_STAKE_FOR_BOOST, "SidePool: not a blueprint");
    _stake(_msgSender(), tokenType, block.timestamp, 0, type(uint16).max, tokenAmountOrID);
  }

  function _unstakeDeposit(Deposit memory deposit) internal {
    _unstake(
      _msgSender(),
      uint256(deposit.tokenType),
      uint256(deposit.lockedFrom),
      uint256(deposit.lockedUntil),
      uint256(deposit.mainIndex),
      uint256(deposit.tokenAmountOrID)
    );
  }

  // In SeedFarm you can unstake directly only blueprints
  // Must be overridden in FarmingPool
  function unstake(uint256 depositIndex) external virtual override {
    Deposit storage deposit = users[_msgSender()].deposits[depositIndex];
    require(deposit.tokenType == BLUEPRINT_STAKE_FOR_BOOST, "SidePool: not a blueprint");
    _unstakeDeposit(deposit);
  }
}
