// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

// Author: Francesco Sullo <francesco@superpower.io>
// Superpower Labs / Syn City

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

// It differs from SynCityCoupons because there are no batch mint and transfer
// they were necessary only for listing on Binance marketplace
contract SynCityCoupons is ERC721, ERC721Enumerable, Ownable {
  using Address for address;
  uint256 public nextTokenId = 1;

  event SwapperSet(address swapper);
  event DepositAddressSet(address depositAddress);
  event BaseTokenURIUpdated(string baseTokenURI);

  string private _baseTokenURI = "https://data.mob.land/genesis_blueprints/json/";

  address public swapper;
  bool public mintEnded;
  bool public transferEnded;

  uint256 public maxSupply;
  address public depositAddress;

  modifier onlySwapper() {
    require(swapper != address(0) && _msgSender() == swapper, "forbidden");
    _;
  }

  constructor(uint256 maxSupply_) ERC721("Syn City Blueprint Coupons", "SYNBC") {
    maxSupply = maxSupply_;
  }

  // implementation required by the compiler, extending ERC721 and ERC721Enumerable
  /**
   *
   * @param from address from where the tokens are being transfer.
   * @param to address to where the tokens are being transfer.
   * @param tokenId Id of the token being transfer.
   */
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId
  ) internal override(ERC721, ERC721Enumerable) {
    super._beforeTokenTransfer(from, to, tokenId);
  }

  // implementation required by the compiler, extending ERC721 and ERC721Enumerable
  function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC721Enumerable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  // The swapper will manage the swap between the coupon and the final token
  /**
   * @param swapper_ is the addres of the owner doing the swap
   */
  function setSwapper(address swapper_) external onlyOwner {
    require(swapper_ != address(0), "swapper cannot be 0x0");
    swapper = swapper_;
    emit SwapperSet(swapper);
  }

  /**
   *
   * @param to address to where the tokens is being minted.
   * @param amount amount of token being minted.
   */
  function mint(address to, uint256 amount) external virtual onlyOwner {
    require(nextTokenId + amount - 1 < 8001, "Out of range");
    uint256 nextId = nextTokenId;
    for (uint256 i = 0; i < amount; i++) {
      _mint(to, nextId++);
    }
    nextTokenId = nextId;
  }

  // swapping, the coupon will be burned
  /**
   * @param tokenId Id of the token being burn
   */
  function burn(uint256 tokenId) external virtual onlySwapper {
    _burn(tokenId);
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return _baseTokenURI;
  }

  function updateBaseURI(string memory baseTokenURI) external onlyOwner {
    _baseTokenURI = baseTokenURI;
    emit BaseTokenURIUpdated(baseTokenURI);
  }
}
