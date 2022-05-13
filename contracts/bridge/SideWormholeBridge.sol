// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// Authors: Francesco Sullo <francesco@sullo.co>

import "@ndujalabs/wormhole-tunnel/contracts/WormholeTunnel.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "../Tesseract.sol";
import "../pool/SeedPool.sol";
import "../utils/PayloadUtils.sol";

contract SideWormholeBridge is PayloadUtils, WormholeTunnel {
  using Address for address;

  //  event PayloadSent(address indexed to, uint16 indexed chainId, uint256 indexed payload, uint64 sequence);
  //  event PayloadReceived(address indexed to, uint256 indexed payload);

  Tesseract public tesseract;
  SeedPool public pool;

  modifier onlyTesseract() {
    require(address(tesseract) == _msgSender(), "SideWormholeBridge: Forbidden");
    _;
  }

  constructor(address tesseract_, address pool_) {
    require(tesseract_.isContract(), "SideWormholeBridge: tesseract_ not a contract");
    require(pool_.isContract(), "SideWormholeBridge: pool_ not a contract");
    tesseract = Tesseract(tesseract_);
    pool = SeedPool(pool_);
  }

  // UNSTAKE starts on the side chain and completes on the main chain
  function wormholeTransfer(
    uint256 payload,
    uint16 recipientChain,
    bytes32 recipient,
    uint32 nonce
  ) public payable override whenNotPaused onlyTesseract returns (uint64) {
    address sender = address(uint160(uint256(recipient)));
    (
      uint256 tokenType,
      uint256 lockedFrom,
      uint256 lockedUntil,
      uint256 mainIndex,
      uint256 tokenAmountOrID
    ) = deserializeDeposit(payload);
    require(tokenType != S_SYNR_SWAP, "SideWormholeBridge: sSYNR swaps cannot be bridged back");
    require(tokenType < BLUEPRINT_STAKE_FOR_BOOST, "SideWormholeBridge: blueprints' unstake does not require bridge");
    pool.unstakeViaBridge(sender, tokenType, lockedFrom, lockedUntil, mainIndex, tokenAmountOrID);
    uint64 sequence = _wormholeTransferWithValue(payload, recipientChain, recipient, nonce, msg.value);
    //    emit PayloadSent(sender, recipientChain, payload, sequence);
    return sequence;
  }

  // STAKE starts on the main chain and completes on the side chain
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
    require(tokenType < BLUEPRINT_STAKE_FOR_BOOST, "SeedFarm: no blueprint allowed here");
    pool.stakeViaBridge(to, tokenType, lockedFrom, lockedUntil, mainIndex, tokenAmountOrID);
  }
}
