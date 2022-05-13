// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "../mocks/previously-deployed/SynCityPasses.sol";

//import "hardhat/console.sol";

contract SynCityPassesMock is SynCityPasses {
  constructor(address _validator) SynCityPasses(_validator) {}

  function mintToken(address to) external {
    _remaining[0]--;
    _safeMint(to, nextTokenId++);
  }
}
