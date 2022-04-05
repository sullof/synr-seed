// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./IPayload.sol";

interface ISynrPool {
  event DepositSaved(address user, uint16 index);

  event DepositUnlocked(address user, uint16 index);

  // can be re-executed to update parameters
  function initPool(
    uint256 minimumLockingTime_, // 3 digits -- 7 days
    uint256 maximumLockingTime_, // 3 digits -- 365 days
    uint256 earlyUnstakePenalty_ // 2 digits -- ex: 30%
  ) external;

  function minimumLockingTime() external view returns (uint256);

  function maximumLockingTime() external view returns (uint256);

  function earlyUnstakePenalty() external view returns (uint256);

  function getVestedPercentage(uint when, uint256 lockedFrom, uint256 lockedUntil) external view returns (uint256);

  function calculatePenaltyForEarlyUnstake(uint when, IPayload.Deposit memory deposit) external view returns (uint256);

  function transferSSynrToTreasury(uint256 amount, address to) external;

  function withdrawPenalties(uint256 amount, address to) external;
}
