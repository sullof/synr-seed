// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// Authors: Francesco Sullo <francesco@sullo.co>
// to be used by Tesseract.sol

interface IWormholeBridge {
  function wormholeTransfer(
    uint256 payload,
    uint16 recipientChain,
    bytes32 recipient,
    uint32 nonce
  ) external payable returns (uint64 sequence);

  function wormholeCompleteTransfer(bytes memory encodedVm) external;
}
