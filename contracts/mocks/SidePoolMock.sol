// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "../pool/SidePool.sol";
import "hardhat/console.sol";

contract SidePoolMock is SidePool {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function initialize(
    address seed_,
    address seed2_,
    address blueprint_
  ) public initializer {
    __SidePool_init(seed_, seed2_, blueprint_);
  }

  function stake(
    uint256 tokenType,
    // solhint-disable-next-line
    uint256 lockupTime,
    uint256 tokenAmountOrID
  ) external virtual override {
    require(
      tokenType == BLUEPRINT_STAKE_FOR_BOOST || (tokenType == BLUEPRINT_STAKE_FOR_SEEDS && nftConf.bPSynrEquivalent != 0),
      "SidePool: stake not allowed"
    );
    _stake(_msgSender(), tokenType, block.timestamp, 0, type(uint16).max, tokenAmountOrID);
  }

  function unstake(uint256 depositIndex) external virtual override {
    Deposit storage deposit = users[_msgSender()].deposits[depositIndex];
    require(
      deposit.tokenType == BLUEPRINT_STAKE_FOR_BOOST || deposit.tokenType == BLUEPRINT_STAKE_FOR_SEEDS,
      "SidePool: not a blueprint"
    );
    _unstakeDeposit(deposit);
  }
}
