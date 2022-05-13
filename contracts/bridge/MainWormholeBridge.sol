// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// Authors: Francesco Sullo <francesco@sullo.co>

import "@ndujalabs/wormhole-tunnel/contracts/WormholeTunnel.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../Tesseract.sol";
import "../pool/MainPool.sol";
import "../utils/PayloadUtils.sol";

contract MainWormholeBridge is PayloadUtils, WormholeTunnel {
  using Address for address;

  //  event PayloadSent(address indexed to, uint16 indexed chainId, uint256 indexed payload, uint64 sequence);
  //  event PayloadReceived(address indexed to, uint256 indexed payload);

  Tesseract public tesseract;
  MainPool public pool;

  modifier onlyTesseract() {
    require(address(tesseract) == _msgSender(), "MainWormholeBridge: Forbidden");
    _;
  }

  constructor(address tesseract_, address pool_) {
    require(tesseract_.isContract(), "MainWormholeBridge: tesseract_ not a contract");
    require(pool_.isContract(), "MainWormholeBridge: pool_ not a contract");
    tesseract = Tesseract(tesseract_);
    pool = MainPool(pool_);
  }

  // STAKE/BURN starts on the main chain and completes on the side chain
  function wormholeTransfer(
    uint256 payload,
    uint16 recipientChain,
    bytes32 recipient,
    uint32 nonce
  ) public payable override whenNotPaused onlyTesseract returns (uint64) {
    address sender = address(uint160(uint256(recipient)));
    payload = pool.stake(sender, payload, recipientChain);
    uint64 sequence = _wormholeTransferWithValue(payload, recipientChain, recipient, nonce, msg.value);
    //    emit PayloadSent(sender, recipientChain, payload, sequence);
    return sequence;
  }

  // STAKE/BURN starts on the side chain and completes on the main chain
  function wormholeCompleteTransfer(bytes memory encodedVm) public virtual override {
    (address to, uint256 payload) = _wormholeCompleteTransfer(encodedVm);
    //    emit PayloadReceived(to, payload);
    _onWormholeCompleteTransfer(to, payload);
  }

  function _onWormholeCompleteTransfer(address to, uint256 payload) internal {
    (
      uint256 tokenType,
      uint256 lockedFrom,
      uint256 lockedUntil,
      uint256 mainIndex,
      uint256 tokenAmountOrID
    ) = deserializeDeposit(payload);
    require(tokenType > S_SYNR_SWAP, "MainWormholeBridge: sSYNR can't be unstaked");
    pool.unstake(to, tokenType, lockedFrom, lockedUntil, mainIndex, tokenAmountOrID);
  }
}
