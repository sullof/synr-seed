// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "../pool/MainPool.sol";

import "hardhat/console.sol";

contract MainPoolMock is MainPool {
  function stake(
    address user,
    uint256 payload,
    uint16 recipientChain
  ) external override returns (uint256) {
    return _stake(user, payload, recipientChain);
  }

  function unstake(
    address user,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 mainIndex,
    uint256 tokenAmountOrID
  ) external override {
    _unstake(user, tokenType, lockedFrom, lockedUntil, mainIndex, tokenAmountOrID);
  }
}
