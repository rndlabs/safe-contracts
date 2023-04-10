import { expect } from "chai";
import hre, { deployments, waffle } from "hardhat";
import "@nomiclabs/hardhat-ethers";
import { AddressZero } from "@ethersproject/constants";
import { getExtensibleFallbackHandler, getSafeTemplate } from "../utils/setup";
import { executeContractCallWithSigners } from "../../src/utils/execution";

describe("ExtensibleHandlerContext", async () => {
    const [user1, user2] = waffle.provider.getWallets();

    const setup = deployments.createFixture(async ({ deployments }) => {
        await deployments.fixture();
        const TestHandler = await hre.ethers.getContractFactory("TestExtensibleDefaultHandler");
        const defaultHandler = await TestHandler.deploy();
        const handler = await getExtensibleFallbackHandler();
        return {
            safe: await getSafeTemplate(),
            handler,
            defaultHandler,
        };
    });

    it("parses information correctly", async () => {
        const { defaultHandler } = await setup();
        const response = await user1.call({
            to: defaultHandler.address,
            data: defaultHandler.interface.encodeFunctionData("dudududu") + user1.address.slice(2) + user2.address.slice(2),
        });
        expect(defaultHandler.interface.decodeFunctionResult("dudududu", response)).to.be.deep.eq([user2.address, user1.address]);
    });

    it("works with the ExtensibleFallbackHandler + Safe", async () => {
        const { safe, handler, defaultHandler } = await setup();
        await safe.setup([user1.address, user2.address], 1, AddressZero, "0x", handler.address, AddressZero, 0, AddressZero);

        const validator = handler.attach(safe.address);

        // set the test default handler
        await executeContractCallWithSigners(safe, validator, "setDefaultFallbackHandler", [defaultHandler.address], [user1, user2]);

        const response = await user1.call({
            to: safe.address,
            data: defaultHandler.interface.encodeFunctionData("dudududu"),
        });

        expect(defaultHandler.interface.decodeFunctionResult("dudududu", response)).to.be.deep.eq([user1.address, safe.address]);
    });
});
