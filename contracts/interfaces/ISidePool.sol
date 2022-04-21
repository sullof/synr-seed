// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

// Author: Francesco Sullo <francesco@sullo.co>
// (c) 2022+ SuperPower Labs Inc.

interface ISidePool {
  event DepositSaved(address user, uint16 mainIndex);

  event DepositUnlocked(address user, uint16 mainIndex);

  event RewardsCollected(address user, uint256 rewards);

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
    uint32 unstakedAt;
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
    // @dev Total passes staked for boost
    uint16 passAmount;
    // @dev Total blueprints staked for boost
    uint16 blueprintsAmount;
    // @dev Total staked amount
    uint256 tokenAmount;
    Deposit[] deposits;
  }

  struct Conf {
    uint16 maximumLockupTime;
    uint32 poolInitAt; // the moment that the pool start operating, i.e., when initPool is first launched
    uint32 rewardsFactor; // initial ratio, decaying every decayInterval of a decayFactor
    uint32 decayInterval; // ex. 7 * 24 * 3600, 7 days
    uint16 decayFactor; // ex. 9850 >> decays of 1.5% every 7 days
    uint32 lastRatioUpdateAt;
    uint16 swapFactor;
    uint16 stakeFactor;
    uint16 taxPoints; // ex 250 = 2.5%
    uint16 burnRatio;
    uint16 priceRatio;
    uint8 coolDownDays; // cool down period for
    uint8 status;
  }

  struct TVL {
    uint16 blueprintAmount;
    uint96 stakedTokenAmount;
  }

  struct NftConf {
    uint32 synrEquivalent; // 100,000
    uint16 sPBoostFactor; // 12500 > 112.5% > +12.5% of boost
    uint32 sPBoostLimit;
    uint16 bPBoostFactor;
    uint32 bPBoostLimit;
  }

  function initPool(
    uint32 rewardsFactor_,
    uint32 decayInterval_,
    uint16 decayFactor_,
    uint16 swapFactor_,
    uint16 stakeFactor_,
    uint16 taxPoints_,
    uint16 burnRatio_,
    uint8 coolDownDays_
  ) external;

  function updateConf(
    uint32 decayInterval_,
    uint16 decayFactor_,
    uint16 swapFactor_,
    uint16 stakeFactor_,
    uint16 taxPoints_,
    uint16 burnRatio_,
    uint8 coolDownDays_
  ) external;

  function updatePriceRatio(uint16 priceRatio_) external;

  function updateOracle(address oracle_) external;

  function pausePool(bool paused) external;

  // Split configuration in two struct to avoid following error calling initPool
  // CompilerError: Stack too deep when compiling inline assembly:
  // Variable value0 is 1 slot(s) too deep inside the stack.
  function updateNftConf(
    uint32 synrEquivalent_,
    uint16 sPBoostFactor_,
    uint32 sPBoostLimit_,
    uint16 bPBoostFactor_,
    uint32 bPBoostLimit_
  ) external;

  function getLockupTime(Deposit memory deposit) external view returns (uint256);

  function yieldWeight(Deposit memory deposit) external view returns (uint256);

  function shouldUpdateRatio() external view returns (bool);

  function updateRatio() external;

  function calculateUntaxedRewards(Deposit memory deposit, uint256 timestamp) external view returns (uint256);

  function calculateTaxOnRewards(uint256 rewards) external view returns (uint256);

  function passForBoostAmount(address user) external view returns (uint256);

  function boostWeight(address user_) external view returns (uint256);

  function collectRewards() external;

  function untaxedPendingRewards(address user_, uint256 timestamp) external view returns (uint256);

  function getDepositByIndex(address user, uint256 mainIndex) external view returns (Deposit memory);

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
