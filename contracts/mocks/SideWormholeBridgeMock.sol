// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// Authors: Francesco Sullo <francesco@sullo.co>

import {BytesLib} from "@ndujalabs/wormhole-tunnel/contracts/libraries/BytesLib.sol";

import "../bridge/SideWormholeBridge.sol";

import "hardhat/console.sol";

contract SideWormholeBridgeMock is SideWormholeBridge {
  constructor(address tesseract_, address pool_) SideWormholeBridge(tesseract_, pool_) {}

  function wormholeCompleteTransfer(bytes memory encodedVm) public override {
    address to = BytesLib.toAddress(encodedVm, 0);
    uint256 payload = BytesLib.toUint256(encodedVm, 20);
    //    (address to, uint256 payload) = _wormholeCompleteTransfer(encodedVm);
    //    emit PayloadReceived(to, payload);
    _onWormholeCompleteTransfer(to, payload);
  }
}
