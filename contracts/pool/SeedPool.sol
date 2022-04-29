// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

// Author: Francesco Sullo <francesco@sullo.co>
// (c) 2022+ SuperPower Labs Inc.

import "./SidePool.sol";
import "hardhat/console.sol";

contract SeedPool is SidePool {
  using SafeMathUpgradeable for uint256;
  using AddressUpgradeable for address;

  modifier onlyFactory() {
    require(factory != address(0) && _msgSender() == factory, "SeedPool: forbidden");
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function initialize(address seedToken_, address blueprint_) public initializer {
    __SidePool_init(seedToken_, seedToken_, blueprint_);
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function setFactory(address farmer_) external virtual onlyOwner {
    require(farmer_.isContract(), "SeedPool: farmer_ not a contract");
    factory = farmer_;
  }

  function stake(
    uint256 tokenType,
    uint256 lockupTime,
    uint256 tokenAmountOrID
  ) external virtual override {
    // mainIndex = type(uint16).max means no meanIndex
    require(tokenType == BLUEPRINT_STAKE_FOR_BOOST, "SeedPool: unsupported token");
    _stake(
      _msgSender(),
      tokenType,
      block.timestamp,
      block.timestamp.add(lockupTime * 1 days),
      type(uint16).max,
      tokenAmountOrID
    );
  }

  function unstake(uint256 depositIndex) external override {
    Deposit memory deposit = users[_msgSender()].deposits[depositIndex];
    require(deposit.tokenType == S_SYNR_SWAP || deposit.tokenType == BLUEPRINT_STAKE_FOR_BOOST, "SeedPool: invalid tokenType");
    _unstakeDeposit(deposit);
  }

  function stakeViaFactory(
    address user_,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 mainIndex,
    uint256 tokenAmountOrID
  ) external onlyFactory {
    require(tokenType < BLUEPRINT_STAKE_FOR_BOOST, "SeedPool: unsupported token");
    _stake(user_, tokenType, lockedFrom, lockedUntil, mainIndex, tokenAmountOrID);
  }

  function unstakeViaFactory(
    address user_,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 mainIndex,
    uint256 tokenAmountOrID
  ) external onlyFactory {
    _unstake(user_, tokenType, lockedFrom, lockedUntil, mainIndex, tokenAmountOrID);
  }

  uint256[50] private __gap;
}
