// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// Author: Francesco Sullo <francesco@sullo.co>
// (c) 2022+ SuperPower Labs Inc.

import "./SidePool.sol";
import "hardhat/console.sol";

contract SeedPool is SidePool {
  using SafeMathUpgradeable for uint256;
  using AddressUpgradeable for address;

  mapping(address => bool) public bridges;

  modifier onlyBridge() {
    require(bridges[_msgSender()], "SeedPool: forbidden");
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function initialize(address seedToken_, address blueprint_) public initializer {
    __SidePool_init(seedToken_, seedToken_, blueprint_);
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function setBridge(address bridge_, bool active) external virtual onlyOwner {
    require(bridge_.isContract(), "SeedPool: bridge_ not a contract");
    if (active) {
      bridges[bridge_] = true;
    } else {
      delete bridges[bridge_];
    }
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
    require(
      deposit.tokenType == S_SYNR_SWAP ||
        deposit.tokenType == BLUEPRINT_STAKE_FOR_BOOST ||
        deposit.tokenType == BLUEPRINT_STAKE_FOR_SEEDS,
      "SeedPool: invalid tokenType"
    );
    _unstakeDeposit(deposit);
  }

  function stakeViaBridge(
    address user_,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 mainIndex,
    uint256 tokenAmountOrID
  ) external onlyBridge {
    require(tokenType < BLUEPRINT_STAKE_FOR_BOOST, "SeedPool: unsupported token");
    _stake(user_, tokenType, lockedFrom, lockedUntil, mainIndex, tokenAmountOrID);
  }

  function unstakeViaBridge(
    address user_,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 mainIndex,
    uint256 tokenAmountOrID
  ) external onlyBridge {
    _unstake(user_, tokenType, lockedFrom, lockedUntil, mainIndex, tokenAmountOrID);
  }

  uint256[50] private __gap;
}
