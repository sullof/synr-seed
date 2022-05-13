// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// Author: Francesco Sullo <francesco@sullo.co>
// (c) 2022+ SuperPower Labs Inc.

interface IMainPool {
  event DepositSaved(address indexed user, uint16 indexed mainIndex);
  event DepositUnlocked(address indexed user, uint16 indexed mainIndex);
  event PoolInitiated(uint16 minimumLockupTime, uint16 earlyUnstakePenalty);
  event PoolPaused(bool isPaused);
  event BridgeSet(address bridge);
  event BridgeRemoved(address bridge);

  struct Deposit {
    // @dev token type (0: sSYNR, 1: SYNR, 2: SYNR Pass...
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
    uint16 otherChain;
    // since the process is asyncronous, the same deposit can be at a different mainIndex
    // on the main net and on the sidechain.
    uint16 mainIndex;
  }

  /// @dev Data structure representing token holder using a pool
  struct User {
    // @dev Total staked SYNR amount
    uint96 synrAmount;
    // @dev Total passes staked
    uint16 passAmount;
    Deposit[] deposits;
  }

  struct Conf {
    uint16 minimumLockupTime;
    uint16 maximumLockupTime;
    uint16 earlyUnstakePenalty;
    uint8 status;
  }

  struct TVL {
    uint16 passAmount;
    uint96 synrAmount;
  }

  function setBridge(address bridge_, bool active) external;

  function getDepositByIndex(address user, uint256 index) external view returns (Deposit memory);

  function getDepositsLength(address user) external view returns (uint256);

  function initPool(uint16 minimumLockupTime_, uint16 earlyUnstakePenalty_) external;

  function getVestedPercentage(
    uint256 when,
    uint256 lockedFrom,
    uint256 lockedUntil
  ) external view returns (uint256);

  function calculatePenaltyForEarlyUnstake(uint256 when, IMainPool.Deposit memory deposit) external view returns (uint256);

  function withdrawSSynr(uint256 amount, address to) external;

  function withdrawPenalties(uint256 amount, address to) external;

  function stake(
    address user,
    uint256 payload,
    uint16 recipientChain
  ) external returns (uint256);

  function unstake(
    address user,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 mainIndex,
    uint256 tokenAmountOrID
  ) external;

  function pausePool(bool paused) external;
}
