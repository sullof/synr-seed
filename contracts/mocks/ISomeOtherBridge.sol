// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// Authors: Francesco Sullo <francesco@sullo.co>
// to be used by Tesseract.sol

interface ISomeOtherBridge {
  function crossTransfer(
    uint256 payload,
    uint8 recipientChain,
    bytes32 salt,
    address recipient,
    uint32 nonce
  ) external payable returns (bool);
}
