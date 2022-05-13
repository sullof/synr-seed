// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract SideToken is ERC20, ERC20Burnable, AccessControl {
  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  bool public allowancePaused = true;

  constructor(string memory name, string memory symbol) ERC20(name, symbol) {
    _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  /**
   * @param to address to mint the token.
   * @param amount amount to be minted.
   */
  function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
    _mint(to, amount);
  }

  function unpauseAllowance() external onlyRole(DEFAULT_ADMIN_ROLE) {
    // after un-pausing the allowance it cannot be paused again
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
