// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

// Author: Francesco Sullo <francesco@sullo.co>
// (c) 2022+ SuperPower Labs Inc.

import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@ndujalabs/wormhole-tunnel/contracts/WormholeTunnelUpgradeable.sol";

import "./pool/SeedPool.sol";
import "./utils/PayloadUtils.sol";
import "hardhat/console.sol";

contract SeedFactory is PayloadUtils, WormholeTunnelUpgradeable {
  using AddressUpgradeable for address;
  using SafeMathUpgradeable for uint256;

  SeedPool public pool;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  function initialize(address pool_) public initializer {
    __WormholeTunnel_init();
    require(pool_.isContract(), "SeedFactory: pool_ not a contract");
    pool = SeedPool(pool_);
  }

  function _authorizeUpgrade(address newImplementation) internal override(WormholeTunnelUpgradeable) onlyOwner {}

  // UNSTAKE starts on the side chain and completes on the main chain
  function wormholeTransfer(
    uint256 payload,
    uint16 recipientChain,
    bytes32 recipient,
    uint32 nonce
  ) public payable override whenNotPaused returns (uint64 sequence) {
    // this limitation is necessary to avoid problems during the unstake
    require(_msgSender() == address(uint160(uint256(recipient))), "SeedFarm: only the sender can receive on other chain");
    (
      uint256 tokenType,
      uint256 lockedFrom,
      uint256 lockedUntil,
      uint256 mainIndex,
      uint256 tokenAmountOrID
    ) = deserializeDeposit(payload);
    require(tokenType != S_SYNR_SWAP, "SeedFarm: sSYNR swaps cannot be bridged back");
    require(tokenType < BLUEPRINT_STAKE_FOR_BOOST, "SeedFarm: blueprints' unstake does not require bridge");
    pool.unstakeViaFactory(_msgSender(), tokenType, lockedFrom, lockedUntil, mainIndex, tokenAmountOrID);
    return _wormholeTransferWithValue(payload, recipientChain, recipient, nonce, msg.value);
  }

  // STAKE starts on the main chain and completes on the side chain
  function wormholeCompleteTransfer(bytes memory encodedVm) public override {
    (address to, uint256 payload) = _wormholeCompleteTransfer(encodedVm);
    _onWormholeCompleteTransfer(to, payload);
  }

  function _onWormholeCompleteTransfer(address to, uint256 payload) internal {
    //    console.log(payload);
    (
      uint256 tokenType,
      uint256 lockedFrom,
      uint256 lockedUntil,
      uint256 mainIndex,
      uint256 tokenAmountOrID
    ) = deserializeDeposit(payload);
    require(tokenType < BLUEPRINT_STAKE_FOR_BOOST, "SeedFarm: no blueprint allowed here");
    pool.stakeViaFactory(to, tokenType, lockedFrom, lockedUntil, mainIndex, tokenAmountOrID);
  }

  uint256[50] private __gap;
}
