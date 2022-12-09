const { mine, mineUpTo, time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { parseUnits } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

describe("Gear Box ", function () {
    let owner, addr1, addr2;
    let coinA, dieselToken, interestModel, poolService, priceOracle, creditFilter, accountFactory, creditManager;
    let minAmount = parseUnits("1", 18);
    let maxAmount = parseUnits("1000", 18);
    let maxLeverage = parseUnits("400", 18); // 400 = x4
    let coinAmount = parseUnits("10000", 18);
    let addLiquidityAmount = parseUnits("100", 18);
    let removeLiquidityAmount = parseUnits("50", 18);

    const treasuryAddress = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
    const uniSwapv2Router = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

    async function deployContractFixture() {
        // Contracts are deployed using the first signer/account by default
        [owner, addr1, addr2, ...addrs] = await ethers.getSigners();

        const CoinA = await ethers.getContractFactory("CoinA");
        coinA = await CoinA.deploy("CoinA", "COA");

        const DieselToken = await ethers.getContractFactory("DieselToken");
        dieselToken = await DieselToken.deploy("DTokenA", "DTA");

        const InterestModel = await ethers.getContractFactory("InterestRateModel");
        interestModel = await InterestModel.deploy();

        const PoolService = await ethers.getContractFactory("PoolService");
        poolService = await PoolService.deploy(
            treasuryAddress,
            coinA.address,
            dieselToken.address,
            interestModel.address
        );

        const PriceOracle = await ethers.getContractFactory("PriceOracle");
        priceOracle = await PriceOracle.deploy();
        // todo oracle add price feed

        const CreditFilter = await ethers.getContractFactory("CreditFilter");
        creditFilter = await CreditFilter.deploy(priceOracle.address, coinA.address);
        // todo add allow tokens & alliw adapter

        const AccountFactory = await ethers.getContractFactory("AccountFactory");
        accountFactory = await AccountFactory.deploy();

        const CreditManager = await ethers.getContractFactory("CreditManager");
        creditManager = await CreditManager.deploy(
            minAmount,
            maxAmount,
            maxLeverage,
            poolService.address,
            creditFilter.address,
            uniSwapv2Router,
            accountFactory.address
        );
        // todo creditManager set contract adapter

        // todo creditFilter connectCreditManager

        await poolService.connectCreditManager(creditManager.address);
        expect(await poolService.creditManagersCanBorrow(owner.address)).to.eq(false);
        expect(await poolService.creditManagersCanBorrow(creditManager.address)).to.eq(true);

        // transfer Dtoken owner to Poolservice
        await dieselToken.transferOwnership(poolService.address);
        expect(await dieselToken.owner()).to.eq(poolService.address);

        // mint coinA & approve
        await coinA.mint(owner.address, coinAmount);
        await coinA.approve(poolService.address, coinAmount);
        expect(await coinA.balanceOf(owner.address)).to.eq(coinAmount);
        expect(await coinA.allowance(owner.address, poolService.address)).to.eq(coinAmount);
    }

    describe("# Pool Service", async () => {
        before(async () => {
            await loadFixture(deployContractFixture);
        });

        it("# add liquidity ", async function () {
            await poolService.addLiquidity(addLiquidityAmount, owner.address, 0);
            expect(await dieselToken.balanceOf(owner.address)).to.eq(addLiquidityAmount);
            expect(await coinA.balanceOf(owner.address)).to.eq(coinAmount.sub(addLiquidityAmount));
        });

        it("remove liquidity", async () => {
            await poolService.removeLiquidity(removeLiquidityAmount, owner.address);
            expect(await dieselToken.balanceOf(owner.address)).to.eq(addLiquidityAmount.sub(removeLiquidityAmount));
        });
    });
});
