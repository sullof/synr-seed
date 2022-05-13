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
}
