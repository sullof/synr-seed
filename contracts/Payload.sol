// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "./interfaces/IPayload.sol";

import "hardhat/console.sol";

contract Payload is IPayload {
  using SafeMathUpgradeable for uint256;

  function version() external pure virtual override returns (uint256) {
    return 1;
  }

  // can be called by web2 app for consistency
  function serializeInput(
    uint256 tokenType, // 1 digit
    uint256 lockupTime, // 4 digits
    uint256 tokenAmountOrID
  ) public pure override returns (uint256) {
    validateInput(tokenType, lockupTime, tokenAmountOrID);
    return tokenType.add(lockupTime.mul(10)).add(tokenAmountOrID.mul(1e5));
  }

  function validateInput(
    uint256 tokenType,
    uint256 lockupTime,
    uint256 tokenAmountOrID
  ) public pure override returns (bool) {
    require(tokenType < 3, "Payload: invalid token type");
    if (tokenType == 2) {
      require(tokenAmountOrID < 889, "Payload: Not a Mobland SYNR Pass token ID");
    } else {
      require(tokenAmountOrID < 1e28, "Payload: tokenAmountOrID out of range");
    }
    require(lockupTime < 1e4, "Payload: lockedTime out of range");
    return true;
  }

  function deserializeInput(uint256 payload)
    public
    pure
    override
    returns (
      uint256 tokenType,
      uint256 lockupTime,
      uint256 tokenAmountOrID
    )
  {
    tokenType = payload.mod(10);
    lockupTime = payload.div(10).mod(1e4);
    tokenAmountOrID = payload.div(1e5);
  }

  function deserializeDeposit(uint256 payload)
    public
    pure
    override
    returns (
      uint256 tokenType,
      uint256 lockedFrom,
      uint256 lockedUntil,
      uint256 mainIndex,
      uint256 tokenAmountOrID
    )
  {
    tokenType = payload.mod(10);
    lockedFrom = payload.div(10).mod(1e10);
    lockedUntil = payload.div(1e11).mod(1e10);
    mainIndex = getIndexFromPayload(payload);
    tokenAmountOrID = payload.div(1e26);
  }

  function getIndexFromPayload(uint256 payload) public pure override returns (uint256) {
    return payload.div(1e21).mod(1e5);
  }
}
