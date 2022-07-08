// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";

contract SideToken is Initializable, OwnableUpgradeable, ERC20Upgradeable, ERC20BurnableUpgradeable {
  using AddressUpgradeable for address;

  bool public allowancePaused;
  mapping(address => bool) public minters;

  modifier onlyMinter() {
    require(minters[_msgSender()], "SideToken: not a minter");
    _;
  }

  // solhint-disable-next-line
  function __SideToken_init(string memory name, string memory symbol) internal initializer {
    __ERC20_init(name, symbol);
    __Ownable_init();
    allowancePaused = true;
  }

  function mint(address to, uint256 amount) public virtual onlyMinter {
    _mint(to, amount);
  }

  function setMinter(address minter, bool enabled) external virtual onlyOwner {
    require(minter.isContract(), "SideToken: minter is not a contract");
    minters[minter] = enabled;
  }

  function unpauseAllowance() external onlyOwner {
    // after un-pausing, the allowance cannot be paused again
    allowancePaused = false;
  }

  function approve(address spender, uint256 amount) public virtual override returns (bool) {
    require(!allowancePaused, "SideToken: allowance not active");
    return super.approve(spender, amount);
  }

  function increaseAllowance(address spender, uint256 addedValue) public virtual override returns (bool) {
    require(!allowancePaused, "SideToken: allowance not active");
    return super.increaseAllowance(spender, addedValue);
  }

  function decreaseAllowance(address spender, uint256 subtractedValue) public virtual override returns (bool) {
    require(!allowancePaused, "SideToken: allowance not active");
    return super.decreaseAllowance(spender, subtractedValue);
  }
}
