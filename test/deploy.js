const { mine, mineUpTo, time, loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { expect } = require("chai");
const { parseUnits } = require("ethers/lib/utils");
const { ethers } = require("hardhat");

describe("Gear Box ", function () {
    let owner, addr1, addr2;
    let dieselToken, interestModel, poolService;
    let coinA;
    let CoinAmount = parseUnits("10000", 18);
    let addLiquidityAmount = parseUnits("100", 18);

    const treasuryAddress = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";

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

        // transfer Dtoken owner to Poolservice
        await dieselToken.transferOwnership(poolService.address);
        expect(await dieselToken.owner()).to.eq(poolService.address);

        // mint coinA & approve
        await coinA.mint(owner.address, CoinAmount);
        await coinA.approve(poolService.address, CoinAmount);
        expect(await coinA.balanceOf(owner.address)).to.eq(CoinAmount);
        expect(await coinA.allowance(owner.address, poolService.address)).to.eq(CoinAmount);
    }

    describe("# Pool Service", async () => {
        before(async () => {
            await loadFixture(deployContractFixture);
        });

        it("# add liquidity ", async function () {
            await poolService.addLiquidity(addLiquidityAmount, owner.address, 0);
            expect(await dieselToken.balanceOf(owner.address)).to.eq(addLiquidityAmount);
        });
    });
});
