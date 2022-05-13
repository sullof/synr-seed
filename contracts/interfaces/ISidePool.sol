// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// Author: Francesco Sullo <francesco@sullo.co>
// (c) 2022+ SuperPower Labs Inc.

interface ISidePool {
  event DepositSaved(address indexed user, uint16 indexed mainIndex);

  event DepositUnlocked(address indexed user, uint16 indexed mainIndex);

  event RewardsCollected(address indexed user, uint256 indexed rewards);

  event PoolInitiatedOrUpdated(
    uint32 rewardsFactor,
    uint32 decayInterval,
    uint16 decayFactor,
    uint32 swapFactor,
    uint32 stakeFactor,
    uint16 taxPoints,
    uint16 burnRatio,
    uint8 coolDownDays
  );

  event PriceRatioUpdated(uint32 priceRatio);
  event NftConfUpdated(
    uint32 sPSynrEquivalent,
    uint32 sPBoostFactor,
    uint32 sPBoostLimit,
    uint32 bPSynrEquivalent,
    uint32 bPBoostFactor,
    uint32 bPBoostLimit
  );
  event PoolPaused(bool isPaused);
  event BridgeSet(address bridge);
  event BridgeRemoved(address bridge);

  struct Deposit {
    // @dev token type (0: sSYNR, 1: SYNR, 2: SYNR Pass)
    uint8 tokenType;
    // @dev locking period - from
    uint32 lockedFrom;
    // @dev locking period - until
    uint32 lockedUntil;
    // @dev token amount staked
    // SYNR maxTokenSupply is 10 billion * 18 decimals = 1e28
    // which is less type(uint96).max (~79e28)
    uint96 tokenAmountOrID;
    uint32 unlockedAt;
    // @dev mainIndex Since the process is asyncronous, the same deposit can be at a different index
    // on the main net and on the sidechain. This guarantees alignment
    uint16 mainIndex;
    // @dev pool token amount staked
    uint128 tokenAmount; //
    // @dev when claimed rewards last time
    uint32 lastRewardsAt;
    // @dev rewards ratio when staked
    uint32 rewardsFactor;
  }

  /// @dev Data structure representing token holder using a pool
  struct User {
    // @dev Total passes staked
    uint16 passAmount;
    // @dev Total blueprints staked
    uint16 blueprintAmount;
    // @dev Total staked amount
    uint128 tokenAmount;
    Deposit[] deposits;
  }

  struct Conf {
    uint16 maximumLockupTime;
    uint32 poolInitAt; // the moment that the pool start operating, i.e., when initPool is first launched
    uint32 rewardsFactor; // initial ratio, decaying every decayInterval of a decayFactor
    uint32 decayInterval; // ex. 7 * 24 * 3600, 7 days
    uint16 decayFactor; // ex. 9850 >> decays of 1.5% every 7 days
    uint32 lastRatioUpdateAt;
    uint32 swapFactor;
    uint32 stakeFactor;
    uint16 taxPoints; // ex 250 = 2.5%
    uint16 burnRatio;
    uint32 priceRatio;
    uint8 coolDownDays; // cool down period for
    uint8 status;
  }

  struct TVL {
    uint16 blueprintAmount;
    uint96 stakedTokenAmount;
  }

  struct NftConf {
    uint32 sPSynrEquivalent; // 100,000
    uint32 sPBoostFactor; // 12500 > 112.5% > +12.5% of boost
    uint32 sPBoostLimit;
    uint32 bPSynrEquivalent;
    uint32 bPBoostFactor;
    uint32 bPBoostLimit;
  }

  function initPool(
    uint32 rewardsFactor_,
    uint32 decayInterval_,
    uint16 decayFactor_,
    uint32 swapFactor_,
    uint32 stakeFactor_,
    uint16 taxPoints_,
    uint16 burnRatio_,
    uint8 coolDownDays_
  ) external;

  function updateConf(
    uint32 decayInterval_,
    uint16 decayFactor_,
    uint32 swapFactor_,
    uint32 stakeFactor_,
    uint16 taxPoints_,
    uint16 burnRatio_,
    uint8 coolDownDays_
  ) external;

  function updatePriceRatio(uint32 priceRatio_) external;

  function updateOracle(address oracle_) external;

  function pausePool(bool paused) external;

  // Split configuration in two struct to avoid following error calling initPool
  // CompilerError: Stack too deep when compiling inline assembly:
  // Variable value0 is 1 slot(s) too deep inside the stack.
  function updateNftConf(
    uint32 sPSynrEquivalent_,
    uint32 sPBoostFactor_,
    uint32 sPBoostLimit_,
    uint32 bPSynrEquivalent_,
    uint32 bPBoostFactor_,
    uint32 bPBoostLimit_
  ) external;

  function getLockupTime(Deposit memory deposit) external view returns (uint256);

  function yieldWeight(Deposit memory deposit) external view returns (uint256);

  function shouldUpdateRatio() external view returns (bool);

  function updateRatio() external;

  function calculateUntaxedRewards(Deposit memory deposit, uint256 timestamp) external view returns (uint256);

  function multiplyByRewardablePeriod(
    uint256 input,
    Deposit memory deposit,
    uint256 timestamp
  ) external view returns (uint256);

  function calculateTaxOnRewards(uint256 rewards) external view returns (uint256);

  function passForBoostAmount(address user) external view returns (uint256);

  function blueprintForBoostAmount(address user) external view returns (uint256);

  function boostWeight(address user_) external view returns (uint256);

  function collectRewards() external;

  function untaxedPendingRewards(address user_, uint256 timestamp) external view returns (uint256);

  function getDepositByIndex(address user, uint256 index) external view returns (Deposit memory);

  function getDepositsLength(address user) external view returns (uint256);

  function canUnstakeWithoutTax(address user, uint256 mainIndex) external view returns (bool);

  function getDepositIndexByMainIndex(address user, uint256 mainIndex) external view returns (uint256, bool);

  function getVestedPercentage(
    uint256 when,
    uint256 lockedFrom,
    uint256 lockedUntil
  ) external view returns (uint256);

  function unstakeIfSSynr(uint256 depositIndex) external;

  function withdrawPenaltiesOrTaxes(
    uint256 amount,
    address beneficiary,
    uint256 what
  ) external;

  function stake(
    uint256 tokenType,
    uint256 lockupTime,
    uint256 tokenAmountOrID
  ) external;

  function unstake(uint256 depositIndex) external;
}
