// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "../Tesseract.sol";

import "hardhat/console.sol";
import "./ISomeOtherBridge.sol";

contract TesseractV2Mock is Tesseract {
  function version() external pure override returns (uint256) {
    return 2;
  }

  function supportedBridgeById(uint256 id) external view virtual override returns (string memory) {
    if (id == 1) {
      return "Wormhole";
    } else if (id == 2) {
      return "SomeOther";
    } else {
      revert("Tesseract: unsupported bridge");
    }
  }

  function crossChainTransfer(
    uint8 bridgeType,
    uint256 payload,
    uint16 recipientChain,
    uint32 nonce
  ) external payable override returns (uint64 sequence) {
    if (bridgeType == 1) {
      return
        IWormholeBridge(bridges[1]).wormholeTransfer(payload, recipientChain, bytes32(uint256(uint160(_msgSender()))), nonce);
    } else {
      revert("Tesseract: unsupported bridge");
    }
  }

  function crossChainTransfer(
    uint8 bridgeType,
    uint256 payload,
    uint8 recipientChain,
    bytes32 salt,
    uint32 nonce
  ) external payable returns (bool) {
    if (bridgeType == 2) {
      return ISomeOtherBridge(bridges[2]).crossTransfer(payload, recipientChain, salt, _msgSender(), nonce);
    } else {
      revert("Tesseract: unsupported bridge");
    }
  }

  uint256[50] private __gap;
}
