const {assert} = require("chai");

const Helpers = {
  initEthers(ethers) {
    this.ethers = ethers;
  },

  async assertThrowsMessage(promise, message) {
    const notThrew = "It did not throw";
    try {
      await promise;
      throw new Error(notThrew);
    } catch (e) {
      const isTrue = e.message.indexOf(message) > -1;
      if (!isTrue) {
        console.error("Expected:", message);
        console.error("Received:", e.message);
        if (e.message !== notThrew) {
          console.error();
          console.error(e);
        }
      }
      assert.isTrue(isTrue);
    }
  },

  async getTimestamp() {
    return (await this.ethers.provider.getBlock()).timestamp;
  },

  async increaseBlockTimestampBy(offset) {
    await this.ethers.provider.send("evm_increaseTime", [offset]);
    await this.ethers.provider.send("evm_mine");
  },

  bytes32Address(address) {
    return "0x000000000000000000000000" + address.replace(/^0x/, "");
  },
};

module.exports = Helpers;
