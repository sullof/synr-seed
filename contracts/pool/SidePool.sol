// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

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
import "../interfaces/IERC721Minimal.sol";
import "../interfaces/ISidePoolViews.sol";

//import "hardhat/console.sol";

abstract contract SidePool is PayloadUtils, ISidePool, TokenReceiver, Initializable, OwnableUpgradeable, UUPSUpgradeable {
  using SafeMathUpgradeable for uint256;
  using AddressUpgradeable for address;

  // users and deposits
  mapping(address => User) public users;
  Conf public conf;
  ExtraConf public extraConf;

  SideToken public rewardsToken;
  SideToken public stakedToken;
  IERC721Minimal public blueprint;

  uint256 public taxes;
  address public oracle;
  ISidePoolViews public poolViews;

  // set the storage to manage future changes
  // keeping the contract upgradeable
  ExtraNftConf[] public extraNftConf;

  modifier onlyOwnerOrOracle() {
    require(_msgSender() == owner() || (oracle != address(0) && _msgSender() == oracle), "SidePool: not owner nor oracle");
    _;
  }

  modifier whenActive() {
    require(conf.status == 1, "SidePool: not initiated or paused");
    _;
  }

  // solhint-disable-next-line
  function __SidePool_init(
    address stakedToken_,
    address rewardsToken_,
    address blueprint_,
    address poolViews_
  ) public initializer {
    __Ownable_init();
    require(stakedToken_.isContract(), "SidePool: stakedToken not a contract");
    require(rewardsToken_.isContract(), "SidePool: rewardsToken not a contract");
    require(blueprint_.isContract(), "SidePool: Blueprint not a contract");
    require(poolViews_.isContract(), "SidePool: poolViews_ not a contract");
    // in SeedFarm, stakedToken and rewardsToken are same token, SEED
    stakedToken = SideToken(stakedToken_);
    rewardsToken = SideToken(rewardsToken_);
    blueprint = IERC721Minimal(blueprint_);
    poolViews = ISidePoolViews(poolViews_);
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function initPool(
    uint32 rewardsFactor_,
    uint32 decayInterval_,
    uint16 decayFactor_,
    uint32 swapFactor_,
    uint32 stakeFactor_,
    uint16 taxPoints_,
    uint8 coolDownDays_
  ) external override onlyOwner {
    require(conf.status == 0, "SidePool: already initiated");
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
      coolDownDays: coolDownDays_,
      status: 1
    });
    extraConf.blueprintAmount = 0;
    extraConf.priceRatio = 10000;
    emit PoolInitiatedOrUpdated(
      rewardsFactor_,
      decayInterval_,
      decayFactor_,
      swapFactor_,
      stakeFactor_,
      taxPoints_,
      coolDownDays_
    );
  }

  // put to zero any parameter that remains the same
  function updateConf(
    uint32 decayInterval_,
    uint16 decayFactor_,
    uint32 swapFactor_,
    uint32 stakeFactor_,
    uint16 taxPoints_,
    uint8 coolDownDays_
  ) external override onlyOwnerOrOracle whenActive {
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
    if (coolDownDays_ > 0) {
      conf.coolDownDays = coolDownDays_;
    }
    emit PoolInitiatedOrUpdated(0, decayInterval_, decayFactor_, swapFactor_, stakeFactor_, taxPoints_, coolDownDays_);
  }

  // put to zero any parameter that remains the same
  function updatePriceRatio(uint32 priceRatio_) external override onlyOwnerOrOracle whenActive {
    if (priceRatio_ > 0) {
      extraConf.priceRatio = priceRatio_;
    }
    emit PriceRatioUpdated(priceRatio_);
  }

  // put to zero any parameter that remains the same
  function updateOracle(address oracle_) external override onlyOwner {
    require(oracle_ != address(0), "SidePool: not a valid address");
    oracle = oracle_;
    emit OracleUpdated(oracle_);
  }

  // put to zero any parameter that remains the same
  function updateExtraConf(
    uint32 sPSynrEquivalent_,
    uint32 sPBoostFactor_,
    uint32 sPBoostLimit_,
    uint32 bPSynrEquivalent_,
    uint32 bPBoostFactor_,
    uint32 bPBoostLimit_
  ) external override onlyOwner whenActive {
    if (sPSynrEquivalent_ > 0) {
      extraConf.sPSynrEquivalent = sPSynrEquivalent_;
    }
    if (sPBoostFactor_ > 0) {
      require(sPBoostFactor_ > 9999, "SidePool: negative boost not allowed");
      extraConf.sPBoostFactor = sPBoostFactor_;
    }
    if (sPBoostLimit_ > 0) {
      require(sPBoostLimit_ >= extraConf.sPSynrEquivalent, "SidePool: invalid boost limit");
      extraConf.sPBoostLimit = sPBoostLimit_;
    }
    if (bPSynrEquivalent_ > 0) {
      extraConf.bPSynrEquivalent = bPSynrEquivalent_;
    }
    if (bPBoostFactor_ > 0) {
      require(bPBoostFactor_ > 9999, "SidePool: negative boost not allowed");
      extraConf.bPBoostFactor = bPBoostFactor_;
    }
    if (bPBoostLimit_ > 0) {
      require(bPBoostLimit_ >= extraConf.bPSynrEquivalent, "SidePool: invalid boost limit");
      extraConf.bPBoostLimit = bPBoostLimit_;
    }
    emit ExtraConfUpdated(sPSynrEquivalent_, sPBoostFactor_, sPBoostLimit_, bPSynrEquivalent_, bPBoostFactor_, bPBoostLimit_);
  }

  function pausePool(bool paused) external onlyOwner {
    conf.status = paused ? 2 : 1;
    emit PoolPaused(paused);
  }

  function version() external pure virtual override returns (uint256) {
    return 1;
  }

  function shouldUpdateRatio() public view override returns (bool) {
    return
      block.timestamp.sub(conf.poolInitAt).div(conf.decayInterval) >
      uint256(conf.lastRatioUpdateAt).sub(conf.poolInitAt).div(conf.decayInterval);
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

  function _calculateBoost(
    uint256 boosted,
    uint256 amount,
    uint256 nftAmount,
    uint256 limit,
    uint256 factor
  ) internal pure returns (uint256, uint256) {
    limit = uint256(nftAmount).mul(limit).mul(1e18);
    if (limit < amount) {
      amount = limit;
    }

    return (amount, boosted.add(amount.mul(factor).div(10000)));
  }

  function collectRewards() public override whenActive {
    _collectRewards(_msgSender());
  }

  /**
   * @notice The reward is collected and the tax is substracted
   * @param user The user collecting the reward
   */
  function _collectRewards(address user) internal {
    uint256 rewards = untaxedPendingRewards(user, block.timestamp);
    if (rewards > 0) {
      uint256 tax = poolViews.calculateTaxOnRewards(conf, rewards);
      rewardsToken.mint(user, rewards.sub(tax));
      rewardsToken.mint(address(this), tax);
      taxes += tax;
      users[user].lastRewardsAt = uint32(block.timestamp);
    }
  }

  /**
   * @notice It returns the total amount of pending claimable rewards
   * @param user The user collecting the reward
   */
  function pendingRewards(address user) public view override returns (uint256) {
    uint256 rewards = untaxedPendingRewards(user, block.timestamp);
    if (rewards > 0) {
      uint256 tax = poolViews.calculateTaxOnRewards(conf, rewards);
      rewards = rewards.sub(tax);
    }
    return rewards;
  }

  /**
   * @param user_ The user collecting the reward
   * @param timestamp Current time of the stake
   * @return the pending rewards that have yet to be taxed
   */
  function untaxedPendingRewards(address user_, uint256 timestamp) public view override returns (uint256) {
    uint256 rewards;
    User storage user = users[user_];
    for (uint256 i = 0; i < user.deposits.length; i++) {
      rewards += poolViews.calculateUntaxedRewards(conf, user.deposits[i], timestamp, user.lastRewardsAt);
    }
    if (rewards > 0) {
      rewards = poolViews.boostRewards(
        extraConf,
        rewards,
        user.stakedAmount,
        user.passAmountForBoost,
        user.blueprintAmountForBoost
      );
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
    require(users[user].deposits[index].lockedFrom > 0, "SidePool: deposit not found");
    return users[user].deposits[index];
  }

  /**
   * @param user address of user
   * @return the ammount of deposits a user has made
   */
  function getDepositsLength(address user) public view override returns (uint256) {
    return users[user].deposits.length;
  }

  function _calculateTokenAmount(uint256 amount, uint256 tokenType) internal view returns (uint256) {
    return amount.mul(tokenType == S_SYNR_SWAP ? conf.swapFactor : conf.stakeFactor).mul(extraConf.priceRatio).div(1000000);
  }

  function _getStakedAndLockedAmount(uint256 tokenType, uint256 tokenAmountOrID) internal view returns (uint256, uint256) {
    uint256 stakedAmount;
    uint256 generator;
    if (tokenType == S_SYNR_SWAP) {
      generator = _calculateTokenAmount(tokenAmountOrID, tokenType);
    } else if (tokenType == SYNR_STAKE) {
      generator = _calculateTokenAmount(tokenAmountOrID, tokenType);
      stakedAmount = tokenAmountOrID;
    } else if (tokenType == SYNR_PASS_STAKE_FOR_SEEDS) {
      stakedAmount = uint256(extraConf.sPSynrEquivalent).mul(1e18);
      generator = _calculateTokenAmount(stakedAmount, tokenType);
    } else if (tokenType == BLUEPRINT_STAKE_FOR_SEEDS) {
      stakedAmount = uint256(extraConf.bPSynrEquivalent).mul(1e18);
      generator = _calculateTokenAmount(stakedAmount, tokenType);
    } else if (tokenType != BLUEPRINT_STAKE_FOR_BOOST && tokenType != SYNR_PASS_STAKE_FOR_BOOST) {
      revert("SidePool: invalid tokenType");
    }
    return (stakedAmount, generator);
  }

  /**
   * @notice stakes if the pool is active
   * @param user address of user being updated
   * @param tokenType identifies the type of transaction being made
   * @param lockedFrom timestamp when locked
   * @param lockedUntil timestamp when can unstake without penalty on MainPool
   * @param tokenAmountOrID ammount of tokens being staked, in the case where a SYNR Pass is being staked, it identified its ID
   * @param mainIndex index of deposit being updated
   */
  function _stake(
    address user,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 mainIndex,
    uint256 tokenAmountOrID
  ) internal virtual whenActive {
    (, bool exists) = getDepositIndexByMainIndex(user, mainIndex);
    require(!exists, "SidePool: payload already used");
    if (users[user].lastRewardsAt == 0) {
      users[user].lastRewardsAt = uint32(block.timestamp);
    }
    updateRatio();
    _collectRewards(user);
    uint256 tokenID;
    (uint256 stakedAmount, uint256 generator) = _getStakedAndLockedAmount(tokenType, tokenAmountOrID);
    // > is more gas efficient than >=
    if (tokenType > BLUEPRINT_STAKE_FOR_BOOST - 1) {
      users[user].blueprintAmount++;
      if (tokenType == BLUEPRINT_STAKE_FOR_BOOST) {
        users[user].blueprintAmountForBoost++;
      }
      tokenID = tokenAmountOrID;
      blueprint.safeTransferFrom(user, address(this), tokenAmountOrID);
      extraConf.blueprintAmount++;
    } else {
      users[user].passAmount++;
      if (tokenType == SYNR_PASS_STAKE_FOR_BOOST) {
        users[user].passAmountForBoost++;
      }
      tokenID = tokenAmountOrID;
    }
    users[user].stakedAmount = uint96(uint256(users[user].stakedAmount).add(stakedAmount));
    users[user].generator = uint128(uint256(users[user].generator).add(generator));
    if (tokenType == S_SYNR_SWAP) {
      lockedUntil = lockedFrom + uint256(conf.coolDownDays).mul(1 days);
    }
    uint256 index = users[user].deposits.length;
    Deposit memory deposit = Deposit({
      tokenType: uint8(tokenType),
      lockedFrom: uint32(lockedFrom),
      lockedUntil: uint32(lockedUntil),
      stakedAmount: uint96(stakedAmount),
      tokenID: uint16(tokenID),
      unlockedAt: 0,
      mainIndex: uint16(mainIndex),
      generator: uint128(generator),
      rewardsFactor: conf.rewardsFactor,
      extra1: 0,
      extra2: 0,
      extra3: 0,
      extra4: 0
    });
    users[user].deposits.push(deposit);
    emit DepositSaved(user, uint16(index));
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
   * @notice unstakes a deposit
   * @param tokenType identifies the type of transaction being made
   * @param lockedFrom timestamp when locked
   * @param lockedUntil timestamp when can unstake without penalty on MainPool
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
  ) internal virtual whenActive {
    (uint256 index, bool exists) = getDepositIndexByMainIndex(user_, mainIndex);
    require(exists, "SidePool: deposit not found");
    Deposit storage deposit = users[user_].deposits[index];
    require(deposit.unlockedAt == 0, "SidePool: deposit already unlocked");
    // < is more gas efficient than <=
    require(tokenType < BLUEPRINT_STAKE_FOR_SEEDS + 1, "SidePool: unsupported tokenType");
    if (tokenType == SYNR_PASS_STAKE_FOR_SEEDS || tokenType == BLUEPRINT_STAKE_FOR_SEEDS) {
      require(lockedUntil < block.timestamp, "SidePool: SYNR Pass and Blueprint used to get SYNR cannot be early unstaked");
    }
    require(
      uint256(deposit.tokenType) == tokenType &&
        uint256(deposit.lockedFrom) == lockedFrom &&
        uint256(deposit.lockedUntil) == lockedUntil &&
        (
          tokenType == SYNR_STAKE
            ? uint256(deposit.stakedAmount) == tokenAmountOrID
            : uint256(deposit.tokenID) == tokenAmountOrID
        ),
      "SidePool: inconsistent deposit"
    );
    _collectRewards(user_);
    if (deposit.tokenType == S_SYNR_SWAP) {
      if (deposit.lockedUntil > block.timestamp) {
        uint256 vestedPercentage = poolViews.getVestedPercentage(block.timestamp, deposit.lockedFrom, deposit.lockedUntil);
        uint256 unstakedAmount = uint256(deposit.generator).mul(vestedPercentage).div(10000);
        stakedToken.mint(_msgSender(), unstakedAmount);
      } else {
        stakedToken.mint(_msgSender(), uint256(deposit.generator));
      }
    } else if (deposit.tokenType > BLUEPRINT_STAKE_FOR_BOOST - 1) {
      users[user_].blueprintAmount--;
      if (tokenType == BLUEPRINT_STAKE_FOR_BOOST) {
        users[user_].blueprintAmountForBoost--;
      }
      blueprint.safeTransferFrom(address(this), user_, uint256(deposit.tokenID));
      extraConf.blueprintAmount--;
    } else if (deposit.tokenType > SYNR_PASS_STAKE_FOR_BOOST - 1) {
      users[user_].passAmount--;
      if (tokenType == SYNR_PASS_STAKE_FOR_BOOST) {
        users[user_].passAmountForBoost--;
      }
    }
    if (deposit.stakedAmount > 0) {
      users[user_].stakedAmount = uint96(uint256(users[user_].stakedAmount).sub(deposit.stakedAmount));
    }
    if (deposit.generator > 0) {
      users[user_].generator = uint128(uint256(users[user_].generator).sub(deposit.generator));
    }
    deposit.unlockedAt = uint32(block.timestamp);
    emit DepositUnlocked(user_, uint16(index));
  }

  /**
   * @notice Withdraws taxes
   * @param amount amount of sSynr to be withdrawn
   * @param beneficiary address to which the withdrawn will go to
   */
  function withdrawTaxes(uint256 amount, address beneficiary) external virtual override onlyOwner {
    require(amount < taxes + 1, "SidePool: amount not available");
    require(beneficiary != address(0), "SidePool: beneficiary cannot be zero address");
    if (amount == 0) {
      amount = taxes;
    }
    taxes -= amount;
    rewardsToken.mint(beneficiary, amount);
  }

  function _unstakeDeposit(Deposit memory deposit) internal {
    _unstake(
      _msgSender(),
      uint256(deposit.tokenType),
      uint256(deposit.lockedFrom),
      uint256(deposit.lockedUntil),
      uint256(deposit.mainIndex),
      deposit.tokenType < SYNR_PASS_STAKE_FOR_BOOST ? uint256(deposit.stakedAmount) : uint256(deposit.tokenID)
    );
  }

  uint256[50] private __gap;
}
