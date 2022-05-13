// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// Author: Francesco Sullo <francesco@sullo.co>
// (c) 2022+ SuperPower Labs Inc.

interface ITesseract {
  function setBridge(uint16 bridgeType, address bridge_) external;

  function supportedBridgeById(uint256 id) external view returns (string memory);

  function crossChainTransfer(
    uint8 bridgeType,
    uint256 payload,
    uint16 recipientChain,
    uint32 nonce
  ) external payable returns (uint64 sequence);

  function completeCrossChainTransfer(uint16 bridgeType, bytes memory encodedVm) external;
}
