// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "../pool/SeedPool.sol";
import "hardhat/console.sol";

contract SeedPoolMock is SeedPool {
  function setBridge(address bridge_, bool active) external virtual override onlyOwner {
    if (active) {
      bridges[bridge_] = true;
    } else {
      delete bridges[bridge_];
    }
  }
}
