// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

// Author: Francesco Sullo <francesco@sullo.co>
// (c) 2022+ SuperPower Labs Inc.

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "../token/TokenReceiver.sol";
import "../utils/PayloadUtils.sol";
import "../interfaces/IMainPool.sol";
import "../token/SyndicateERC20.sol";
import "../token/SyntheticSyndicateERC20.sol";
import "../token/SynCityPasses.sol";

import "hardhat/console.sol";

contract MainPool is IMainPool, PayloadUtils, TokenReceiver, Initializable, OwnableUpgradeable, UUPSUpgradeable {
  using AddressUpgradeable for address;
  using SafeMathUpgradeable for uint256;

  // users and deposits
  mapping(address => User) public users;
  Conf public conf;

  SyndicateERC20 public synr;
  SyntheticSyndicateERC20 public sSynr;
  SynCityPasses public pass;

  uint256 public penalties;

  address public factory;

  TVL public tvl;

  modifier onlyFactory() {
    require(factory != address(0) && _msgSender() == factory, "SeedPool: forbidden");
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer {}

  // solhint-disable-next-line
  function initialize(
    address synr_,
    address sSynr_,
    address pass_
  ) public initializer {
    __Ownable_init();
    require(synr_.isContract(), "synr_ not a contract");
    require(sSynr_.isContract(), "sSynr_ not a contract");
    require(pass_.isContract(), "pass_ not a contract");
    synr = SyndicateERC20(synr_);
    sSynr = SyntheticSyndicateERC20(sSynr_);
    pass = SynCityPasses(pass_);
  }

  function _updateTvl(
    uint256 tokenType,
    uint256 tokenAmount,
    bool increase
  ) internal {
    if (increase) {
      if (tokenType == SYNR_STAKE) {
        tvl.synrAmount += uint96(tokenAmount);
      } else if (tokenType == SYNR_PASS_STAKE_FOR_BOOST || tokenType == SYNR_PASS_STAKE_FOR_SEEDS) {
        tvl.passAmount++;
      }
    } else {
      if (tokenType == SYNR_STAKE) {
        tvl.synrAmount = uint96(uint256(tvl.synrAmount).sub(tokenAmount));
      } else {
        tvl.passAmount--;
      }
    }
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function setFactory(address farmer_) external onlyOwner {
    require(farmer_.isContract(), "SeedPool: farmer_ not a contract");
    factory = farmer_;
  }

  function initPool(uint16 minimumLockupTime_, uint16 earlyUnstakePenalty_) external override onlyOwner {
    require(sSynr.isOperatorInRole(address(this), 0x0004_0000), "MainPool: contract cannot receive sSYNR");
    require(conf.maximumLockupTime == 0, "MainPool: already initiated");
    conf = Conf({
      minimumLockupTime: minimumLockupTime_,
      maximumLockupTime: 365,
      earlyUnstakePenalty: earlyUnstakePenalty_,
      status: 1
    });
  }

  function version() external pure virtual override returns (uint256) {
    return 1;
  }

  function pausePool(bool paused) external onlyOwner {
    conf.status = paused ? 2 : 1;
  }

  /**
   * @notice Converts the input payload to the transfer payload
   * @param deposit The deposit
   * @return the payload, an encoded uint256
   */
  function _fromDepositToTransferPayload(Deposit memory deposit) internal pure returns (uint256) {
    return
      uint256(deposit.tokenType)
        .add(uint256(deposit.lockedFrom).mul(100))
        .add(uint256(deposit.lockedUntil).mul(1e12))
        .add(uint256(deposit.mainIndex).mul(1e22))
        .add(uint256(deposit.tokenAmountOrID).mul(1e27));
  }

  /**
   * @notice updates the user with the staked amount or the pass amount and creates new deposit for the user
   * @param user address of user being updated
   * @param tokenType identifies the type of transaction being made, 0=SSYNR, 1=SYNR, 2 or 3 = SYNR PASS.
   * @param lockedFrom timestamp when locked
   * @param lockedUntil timestamp when can unstake without penalty
   * @param tokenAmountOrID ammount of tokens being staked, in the case where a SYNR Pass is being staked, it identified its ID
   * @param otherChain chainID of recieving chain
   * @param mainIndex index of deposit being updated
   * @return the new deposit
   */
  function _updateUserAndAddDeposit(
    address user,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 tokenAmountOrID,
    uint16 otherChain,
    uint256 mainIndex
  ) internal returns (Deposit memory) {
    if (tokenType == SYNR_STAKE) {
      users[user].synrAmount += uint96(tokenAmountOrID);
    } else if (tokenType == SYNR_PASS_STAKE_FOR_BOOST || tokenType == SYNR_PASS_STAKE_FOR_SEEDS) {
      users[user].passAmount++;
    }
    _updateTvl(tokenType, tokenAmountOrID, true);
    Deposit memory deposit = Deposit({
      tokenType: uint8(tokenType),
      lockedFrom: uint32(lockedFrom),
      lockedUntil: uint32(lockedUntil),
      tokenAmountOrID: uint96(tokenAmountOrID),
      unstakedAt: 0,
      otherChain: otherChain,
      mainIndex: uint16(mainIndex)
    });
    users[user].deposits.push(deposit);
    return deposit;
  }

  /**
   * @notice Searches for deposit from the user and its index
   * @param user address of user who made deposit being searched
   * @param index index of the deposit being searched
   * @return the deposit
   */
  function getDepositByIndex(address user, uint256 index) public view override returns (Deposit memory) {
    require(users[user].deposits[index].lockedFrom > 0, "MainPool: deposit not found");
    return users[user].deposits[index];
  }

  /**
   * @param user address of user
   * @return the ammount of deposits a user has made
   */
  function getDepositsLength(address user) public view override returns (uint256) {
    return users[user].deposits.length;
  }

  /**
   * @notice makes the deposit
   * @param tokenType identifies the type of transaction being made, 0=SSYNR, 1=SYNR, 2 or 3 = SYNR PASS.
   * @param lockupTime time the staking will take
   * @param tokenAmountOrID ammount of tokens being staked, in the case where a SYNR Pass is being staked, it identified its ID
   * @param otherChain chainID of recieving chain
   * @return the TransferPayload calculated from the deposit
   */
  function _makeDeposit(
    address user,
    uint256 tokenType,
    uint256 lockupTime,
    uint256 tokenAmountOrID,
    uint16 otherChain
  ) internal returns (uint256) {
    validateInput(tokenType, lockupTime, tokenAmountOrID);
    if (tokenType == S_SYNR_SWAP || tokenType == SYNR_STAKE) {
      require(tokenAmountOrID >= 1e18, "MainPool: must stake at least one unity");
    }
    if (tokenType == SYNR_STAKE || tokenType == SYNR_PASS_STAKE_FOR_SEEDS) {
      require(
        lockupTime > conf.minimumLockupTime - 1 && lockupTime < conf.maximumLockupTime + 1,
        "MainPool: invalid lockupTime type"
      );
    }
    // Contract must be approved as spender.
    // It will throw if the balance is insufficient
    if (tokenType == S_SYNR_SWAP) {
      // MainPool must be whitelisted to receive sSYNR
      sSynr.transferFrom(user, address(this), tokenAmountOrID);
    } else if (tokenType == SYNR_STAKE) {
      // MainPool must be approved to spend the SYNR
      synr.safeTransferFrom(user, address(this), tokenAmountOrID, "");
    } else {
      // tokenType 2 and 3
      // SYNR Pass
      // MainPool must be approved to make the transfer
      pass.safeTransferFrom(user, address(this), tokenAmountOrID);
    }
    return _fromDepositToTransferPayload(_updateUser(user, tokenType, lockupTime, tokenAmountOrID, otherChain));
  }

  /**
   * @notice updates the user, calls _updateUserAndAddDeposit
   * @param user address of user being updated
   * @param tokenType identifies the type of transaction being made, 0=SSYNR, 1=SYNR, 2 or 3 = SYNR PASS.
   * @param lockupTime time the staking will take
   * @param tokenAmountOrID ammount of tokens being staked, in the case where a SYNR Pass is being staked, it identified its ID
   * @param otherChain chainID of recieving chain
   * @return the deposit
   */
  function _updateUser(
    address user,
    uint256 tokenType,
    uint256 lockupTime,
    uint256 tokenAmountOrID,
    uint16 otherChain
  ) internal returns (Deposit memory) {
    uint256 lockedUntil = tokenType == SYNR_STAKE || tokenType == SYNR_PASS_STAKE_FOR_SEEDS
      ? uint32(block.timestamp.add(lockupTime * 1 days))
      : 0;
    Deposit memory deposit = _updateUserAndAddDeposit(
      user,
      tokenType,
      uint32(block.timestamp),
      lockedUntil,
      tokenAmountOrID,
      otherChain,
      getDepositsLength(user)
    );
    return deposit;
  }

  /**
   * @notice unstakes a deposit, calculates penalty for early unstake
   * @param user address of user
   * @param tokenType identifies the type of transaction being made, 0=SSYNR, 1=SYNR, 2 or 3 = SYNR PASS.
   * @param lockedFrom timestamp when locked
   * @param lockedUntil timestamp when can unstake without penalty
   * @param mainIndex index of deposit
   * @param tokenAmountOrID ammount of tokens being staked, in the case where a SYNR Pass is being staked, it identified its ID
   */
  function _unstake(
    address user,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 mainIndex,
    uint256 tokenAmountOrID
  ) internal {
    require(tokenType > S_SYNR_SWAP, "MainPool: sSYNR can not be unstaked");
    if (tokenType == SYNR_PASS_STAKE_FOR_SEEDS) {
      require(lockedUntil < block.timestamp, "MainPool: SYNR Pass cannot be early unstaked");
    }
    if (tokenType == SYNR_STAKE) {
      users[user].synrAmount = uint96(uint256(users[user].synrAmount).sub(tokenAmountOrID));
    } else {
      users[user].passAmount = uint16(uint256(users[user].passAmount).sub(1));
    }
    _updateTvl(tokenType, tokenAmountOrID, false);
    Deposit storage deposit = users[user].deposits[mainIndex];
    require(
      uint256(deposit.mainIndex) == mainIndex &&
        uint256(deposit.tokenType) == tokenType &&
        uint256(deposit.lockedFrom) == lockedFrom &&
        uint256(deposit.lockedUntil) == lockedUntil &&
        uint256(deposit.tokenAmountOrID) == tokenAmountOrID,
      "MainPool: inconsistent deposit"
    );
    require(deposit.unstakedAt == 0, "MainPool: deposit already unstaked");
    if (tokenType == SYNR_PASS_STAKE_FOR_BOOST || tokenType == SYNR_PASS_STAKE_FOR_SEEDS) {
      pass.safeTransferFrom(address(this), user, uint256(tokenAmountOrID));
    } else {
      uint256 penalty = calculatePenaltyForEarlyUnstake(block.timestamp, deposit);
      uint256 amount = uint256(tokenAmountOrID).sub(penalty);
      synr.safeTransferFrom(address(this), user, amount, "");
      if (penalty > 0) {
        penalties += penalty;
      }
    }
    deposit.unstakedAt = uint32(block.timestamp);
    emit DepositUnlocked(user, uint16(mainIndex));
  }

  /**
   * @notice gets Percentage Vested at a certain timestamp
   * @param when timestamp where percentage will be calculated
   * @param lockedFrom timestamp when locked
   * @param lockedUntil timestamp when can unstake without penalty
   * @return the percentage vested
   */
  function getVestedPercentage(
    uint256 when,
    uint256 lockedFrom,
    uint256 lockedUntil
  ) public pure override returns (uint256) {
    if (lockedUntil == 0) {
      return 10000;
    }
    uint256 lockupTime = lockedUntil.sub(lockedFrom);
    if (lockupTime == 0) {
      return 10000;
    }
    uint256 vestedTime = when.sub(lockedFrom);
    return vestedTime.mul(10000).div(lockupTime);
  }

  /**
   * @notice calculates penalty when unstaking SYNR before period is up
   * @param when timestamp where percentage will be calculated
   * @param deposit deposit from where penalty is to be calculated
   * @return the penalty, if any
   */
  function calculatePenaltyForEarlyUnstake(uint256 when, Deposit memory deposit) public view override returns (uint256) {
    if (when > uint256(deposit.lockedUntil)) {
      return 0;
    }
    uint256 vestedPercentage = getVestedPercentage(when, uint256(deposit.lockedFrom), uint256(deposit.lockedUntil));
    uint256 unvestedAmount = uint256(deposit.tokenAmountOrID).mul(vestedPercentage).div(10000);
    return unvestedAmount.mul(conf.earlyUnstakePenalty).div(10000);
  }

  /**
   * @notice Withdraws SSYNR that has been Swapped to the contract
   * @param amount amount of ssynr to be withdrawn
   * @param beneficiary address to which the withdrawl will go to
   */
  function withdrawSSynr(uint256 amount, address beneficiary) external override onlyOwner {
    uint256 availableAmount = sSynr.balanceOf(address(this));
    require(availableAmount > 0 && amount <= availableAmount, "MainPool: sSYNR amount not available");
    if (amount == 0) {
      amount = availableAmount;
    }
    // the approve is necessary, because of a bug in the sSYNR contract
    sSynr.approve(address(this), amount);
    // beneficiary must be whitelisted to receive sSYNR
    sSynr.transferFrom(address(this), beneficiary, amount);
  }

  /**
   * @notice Withdraws SYNR that has been collected as tax for unstaking early
   * @param amount amount of ssynr to be withdrawn
   * @param beneficiary address to which the withdrawl will go to
   */
  function withdrawPenalties(uint256 amount, address beneficiary) external override onlyOwner {
    require(penalties > 0 && amount <= penalties, "MainPool: amount not available");
    if (amount == 0) {
      amount = penalties;
    }
    penalties -= amount;
    synr.safeTransferFrom(address(this), beneficiary, amount, "");
  }

  /**
   * @notice stakes the payload if the pool is active
   * @param user address of user
   * @param payload an uint256 encoded with the information of the deposit
   * @param recipientChain chain to where the transfer will go
   */
  function _stake(
    address user,
    uint256 payload,
    uint16 recipientChain
  ) internal {
    require(conf.status == 1, "MainPool: not initiated or paused");
    (uint256 tokenType, uint256 lockupTime, uint256 tokenAmountOrID) = deserializeInput(payload);
    require(conf.minimumLockupTime > 0, "MainPool: pool not alive");
    payload = _makeDeposit(user, tokenType, lockupTime, tokenAmountOrID, recipientChain);
    emit DepositSaved(user, uint16(getIndexFromPayload(payload)));
  }

  function stake(
    address user,
    uint256 payload,
    uint16 recipientChain
  ) external virtual onlyFactory {
    _stake(user, payload, recipientChain);
  }

  function unstake(
    address user,
    uint256 tokenType,
    uint256 lockedFrom,
    uint256 lockedUntil,
    uint256 mainIndex,
    uint256 tokenAmountOrID
  ) external virtual onlyFactory {
    _unstake(user, tokenType, lockedFrom, lockedUntil, mainIndex, tokenAmountOrID);
  }

  uint256[50] private __gap;
}
