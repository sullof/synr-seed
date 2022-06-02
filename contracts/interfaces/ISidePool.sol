// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// Author: Francesco Sullo <francesco@sullo.co>
// (c) 2022+ SuperPower Labs Inc.

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./ISideUser.sol";

interface ISidePool is ISideUser {
  event RewardsCollected(address indexed user, uint256 indexed rewards);
  event OracleUpdated(address oracle);

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
  event NftConfUpdated(uint32 sPSynrEquivalent, uint32 sPBoostFactor, uint32 bPSynrEquivalent, uint32 bPBoostFactor);
  event PoolPaused(bool isPaused);
  event BridgeSet(address bridge);
  event BridgeRemoved(address bridge);

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

  struct ExtraConf {
    // reserved for future variables
    uint32 reserved1;
    uint32 reserved2;
    uint32 reserved3;
    uint32 reserved4;
    uint32 reserved5;
    uint32 reserved6;
    uint32 reserved7;
    uint32 reserved8;
  }

  struct TVL {
    uint16 blueprintAmount;
    uint96 stakedTokenAmount;
  }

  struct NftConf {
    uint32 sPSynrEquivalent; // 100,000
    uint32 sPBoostFactor; // 12500 > 112.5% > +12.5% of boost
    uint32 bPSynrEquivalent;
    uint32 bPBoostFactor;
  }

  struct ExtraNftConf {
    IERC721 token;
    uint16 boostFactor; // 12500 > 112.5% > +12.5% of boost
    uint32 boostLimit;
  }

  // functions

  function initPool(
    uint32 rewardsFactor,
    uint32 decayInterval,
    uint16 decayFactor,
    uint32 swapFactor,
    uint32 stakeFactor,
    uint16 taxPoints,
    uint16 burnRatio,
    uint8 coolDownDays
  ) external;

  function updateConf(
    uint32 decayInterval,
    uint16 decayFactor,
    uint32 swapFactor,
    uint32 stakeFactor,
    uint16 taxPoints,
    uint16 burnRatio,
    uint8 coolDownDays
  ) external;

  function updatePriceRatio(uint32 priceRatio_) external;

  function updateOracle(address oracle_) external;

  function pausePool(bool paused) external;

  // Split configuration in two struct to avoid following error calling initPool
  // CompilerError: Stack too deep when compiling inline assembly:
  // Variable value0 is 1 slot(s) too deep inside the stack.
  function updateNftConf(
    uint32 sPSynrEquivalent,
    uint32 sPBoostFactor,
    uint32 bPSynrEquivalent,
    uint32 bPBoostFactor
  ) external;

  function getLockupTime(Deposit memory deposit) external view returns (uint256);

  function yieldWeight(Deposit memory deposit) external view returns (uint256);

  function shouldUpdateRatio() external view returns (bool);

  function updateRatio() external;

  function calculateUntaxedRewards(
    address user,
    uint256 depositIndex,
    uint256 timestamp
  ) external view returns (uint256);

  function calculateTaxOnRewards(uint256 rewards) external view returns (uint256);

  function passForBoostAmount(address user) external view returns (uint256);

  function blueprintForBoostAmount(address user) external view returns (uint256);

  function boostWeight(address user) external view returns (uint256);

  function collectRewards() external;

  function pendingRewards(address user) external view returns (uint256);

  function untaxedPendingRewards(address user, uint256 timestamp) external view returns (uint256);

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

  function unstake(Deposit memory deposit) external;
}
