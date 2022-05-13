// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "./SideToken.sol";

contract WeedToken is SideToken {
  constructor() SideToken("Mobland Weed Token", "WEED") {}
}
