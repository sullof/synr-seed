// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// Authors: Francesco Sullo <francesco@sullo.co>

import "@ndujalabs/wormhole-tunnel/contracts/WormholeTunnelUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

import "../Tesseract.sol";
import "../utils/PayloadUtils.sol";

contract WormholeBridge is PayloadUtils, WormholeTunnelUpgradeable {
  using AddressUpgradeable for address;
  using ECDSAUpgradeable for bytes32;

  Tesseract public tesseract;
  address public pool;
  address public validator;

  modifier onlyTesseract() {
    require(address(tesseract) == _msgSender(), "MainWormholeBridge: Forbidden");
    _;
  }

  // solhint-disable-next-line
  function __WormholeBridge_init(address tesseract_, address pool_) public virtual initializer {
    __WormholeTunnel_init();
    require(tesseract_.isContract(), "WormholeBridge: tesseract_ not a contract");
    require(pool_.isContract(), "WormholeBridge: pool_ not a contract");
    tesseract = Tesseract(tesseract_);
    pool = pool_;
  }

  function setValidator(address validator_) external onlyOwner {
    require(validator_ != address(0), "MainPool: address zero not allowed");
    validator = validator_;
  }

  function updatePool(address pool_) external onlyOwner {
    require(pool_.isContract(), "WormholeBridge: pool_ not a contract");
    pool = pool_;
  }

  // must be overwritten
  function wormholeTransfer(
    // solhint-disable-next-line
    uint256 payload,
    // solhint-disable-next-line
    uint16 recipientChain,
    // solhint-disable-next-line
    bytes32 recipient,
    // solhint-disable-next-line
    uint32 nonce
  ) public payable virtual override returns (uint64) {
    return uint64(0);
  }

  // must be overwritten
  function wormholeCompleteTransfer(bytes memory encodedVm) public virtual override {}

  // must be overwritten
  function completeTransferIfBridgeFails(
    address to,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 mainIndex,
    uint256 tokenAmountOrID,
    bytes memory signature
  ) external virtual {
    require(
      isSignedByValidator(encodeForSignature(to, tokenType, lockedFrom, lockedUntil, mainIndex, tokenAmountOrID), signature),
      "WormholeBridge: invalid signature"
    );
  }

  // this is called internally
  // and externally by the web3 app to test the validation
  function isSignedByValidator(bytes32 _hash, bytes memory _signature) public view returns (bool) {
    return validator != address(0) && validator == _hash.recover(_signature);
  }

  // this is called internally
  // and externally by the web3 app
  function encodeForSignature(
    address to,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 mainIndex,
    uint256 tokenAmountOrID
  ) public view returns (bytes32) {
    return
      keccak256(
        abi.encodePacked(
          "\x19\x01", // EIP-191
          block.chainid,
          to,
          tokenType,
          lockedFrom,
          lockedUntil,
          mainIndex,
          tokenAmountOrID
        )
      );
  }
}
