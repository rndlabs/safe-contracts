import { expect } from "chai";
import hre, { deployments, waffle } from "hardhat";
import "@nomiclabs/hardhat-ethers";
import { AddressZero } from "@ethersproject/constants";
import { deployContract, getExtensibleDefaultFallbackHandler, getExtensibleFallbackHandler, getSafeWithOwners } from "../utils/setup";
import { executeContractCallWithSigners } from "../../src/utils/execution";
import { killLibContract } from "../utils/contracts";

describe("ExtensibleFallbackHandler", async () => {
    const [user1, user2] = waffle.provider.getWallets();

    const setupTests = deployments.createFixture(async ({ deployments }) => {
        await deployments.fixture();
        const signLib = await (await hre.ethers.getContractFactory("SignMessageLib")).deploy();
        const handler = await getExtensibleFallbackHandler();
        const defaultHandler = await getExtensibleDefaultFallbackHandler();
        const defaultHandlerAddress = defaultHandler.address;
        const signerSafe = await getSafeWithOwners([user1.address], 1, handler.address);
        const safe = await getSafeWithOwners([user1.address, user2.address, signerSafe.address], 2, handler.address);
        const validator = handler.attach(safe.address);
        const validatorDefault = defaultHandler.attach(safe.address);
        const killLib = await killLibContract(user1);

        const mirrorSource = `
        contract Mirror {
            function handle(address safe, address sender, bytes calldata data) external returns (bytes memory result) {
                return msg.data;
            }

            function lookAtMe() public returns (bytes memory) {
                return msg.data;
            }

            function nowLookAtYou(address you, string memory howYouLikeThat) public returns (bytes memory) {
                return msg.data;
            }
        }`;

        const otherSource = `
        contract Other {
            string public constant NAME = "Other Callback Handler";
        }`;

        const mirror = await deployContract(user1, mirrorSource);
        const other = await deployContract(user1, otherSource);

        return {
            safe,
            handler,
            killLib,
            signLib,
            signerSafe,
            mirror,
            other,
            validator,
            validatorDefault,
            defaultHandlerAddress,
        };
    });

    describe("setSafeMethod", async () => {
        it("reverts if called by non-safe", async () => {
            const { handler, mirror } = await setupTests();

            // Check revert
            await expect(handler.setSafeMethod("0xdededede", mirror.address)).to.be.revertedWith("only safe can call this method");
        });
        it("emits added / changed / removed events", async () => {
            const { safe, handler, validator, mirror } = await setupTests();

            // Check event when adding
            await expect(executeContractCallWithSigners(safe, validator, "setSafeMethod", ["0xdededede", mirror.address], [user1, user2]))
                .to.emit(handler, "AddedSafeMethod")
                .withArgs(safe.address, "0xdededede", mirror.address);

            // Check the event when changing
            await expect(
                executeContractCallWithSigners(
                    safe,
                    validator,
                    "setSafeMethod",
                    ["0xdededede", "0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD"],
                    [user1, user2],
                ),
            )
                .to.emit(handler, "ChangedSafeMethod")
                .withArgs(safe.address, "0xdededede", mirror.address, "0xdeaDDeADDEaDdeaDdEAddEADDEAdDeadDEADDEaD");

            // Check the event when removing
            await expect(executeContractCallWithSigners(safe, validator, "setSafeMethod", ["0xdededede", AddressZero], [user1, user2]))
                .to.emit(handler, "RemovedSafeMethod")
                .withArgs(safe.address, "0xdededede");
        });

        it("is correctly set", async () => {
            const { safe, validator, mirror } = await setupTests();
            const tx = {
                to: safe.address,
                data: mirror.interface.encodeFunctionData("lookAtMe"),
            };

            // Confirm method handler is not set (call should revert)
            await expect(user1.call(tx)).to.be.reverted;

            // Setup the method handler
            await executeContractCallWithSigners(safe, validator, "setSafeMethod", ["0x7f8dc53c", mirror.address], [user1, user2]);

            // Check that the method handler is called
            expect(await user1.call(tx)).to.be.eq(
                "0x" +
                    "0000000000000000000000000000000000000000000000000000000000000020" +
                    "00000000000000000000000000000000000000000000000000000000000000a4" +
                    "443ce2a8" + // the `handle(addr,addr,bytes) selector for the `IFallbackMethod`
                    "000000000000000000000000" +
                    safe.address.slice(2).toLowerCase() +
                    "000000000000000000000000" +
                    user1.address.slice(2).toLowerCase() +
                    "0000000000000000000000000000000000000000000000000000000000000060" +
                    "0000000000000000000000000000000000000000000000000000000000000004" +
                    "7f8dc53c" + // the `lookAtMe()` selector
                    "00000000000000000000000000000000000000000000000000000000" +
                    "00000000000000000000000000000000000000000000000000000000",
            );
        });
    });

    describe("setDefaultFallbackHandler", async () => {
        it("reverts if called by non-safe", async () => {
            const { handler, mirror } = await setupTests();

            // Check revert
            await expect(handler.setDefaultFallbackHandler(mirror.address)).to.be.revertedWith("only safe can call this method");
        });

        it("reverts if calling a non-existant method", async () => {
            const { safe, mirror } = await setupTests();

            const tx = {
                to: safe.address,
                data: mirror.interface.encodeFunctionData("lookAtMe"),
            };

            // Confirm method handler is not set (call should revert)
            await expect(user1.call(tx)).to.be.reverted;
        });

        it("uses default fallback", async () => {
            const { validatorDefault } = await setupTests();

            // Check that the default fallback is called
            expect(await validatorDefault.NAME()).to.be.eq("Default Callback Handler");
        });

        it("emits changed events", async () => {
            const { safe, handler, validator, validatorDefault, mirror, other, defaultHandlerAddress } = await setupTests();

            let tx = {
                to: safe.address,
                data: mirror.interface.encodeFunctionData("lookAtMe"),
            };

            // Confirm method handler is not set (call should revert)
            await expect(user1.call(tx)).to.be.reverted;

            // Check the event when changing the default handler
            await expect(executeContractCallWithSigners(safe, validator, "setDefaultFallbackHandler", [mirror.address], [user1, user2]))
                .to.emit(handler, "ChangedDefaultFallbackHandler")
                .withArgs(safe.address, defaultHandlerAddress, mirror.address);

            // Now the tx should succeed
            expect(await user1.call(tx)).to.be.eq(
                "0x" +
                    "0000000000000000000000000000000000000000000000000000000000000020" +
                    "000000000000000000000000000000000000000000000000000000000000002c" +
                    "7f8dc53c" + // the `lookAtMe()` selector
                    safe.address.slice(2).toLowerCase() + // the safe address
                    user1.address.slice(2).toLowerCase() + // the original sender
                    "0000000000000000000000000000000000000000",
            );

            // Check the event when changing to to another handler
            await expect(executeContractCallWithSigners(safe, validator, "setDefaultFallbackHandler", [other.address], [user1, user2]))
                .to.emit(handler, "ChangedDefaultFallbackHandler")
                .withArgs(safe.address, mirror.address, other.address);

            tx = {
                to: safe.address,
                data: other.interface.encodeFunctionData("NAME"),
            };

            // Confirm the new handler is called
            const result = await user1.call(tx);
            expect(other.interface.decodeFunctionResult("NAME", result)[0]).to.be.eq("Other Callback Handler");

            // Check setting to zero should restore the default handler
            await expect(executeContractCallWithSigners(safe, validator, "setDefaultFallbackHandler", [AddressZero], [user1, user2]))
                .to.emit(handler, "ChangedDefaultFallbackHandler")
                .withArgs(safe.address, other.address, defaultHandlerAddress);

            // Check that the default fallback is called
            expect(await validatorDefault.NAME()).to.be.eq("Default Callback Handler");
        });

        it("can override individual methods", async () => {
            const { safe, handler, validator, mirror, other } = await setupTests();

            let tx = {
                to: safe.address,
                data: "0xdededede",
            };

            // Confirm method handler is not set (call should revert)
            await expect(user1.call(tx)).to.be.reverted;

            // Set the method handler to the mirror
            await executeContractCallWithSigners(safe, validator, "setSafeMethod", [tx.data, mirror.address], [user1, user2]);

            // Now the tx should succeed
            expect(await user1.call(tx)).to.be.eq(
                "0x" +
                    "0000000000000000000000000000000000000000000000000000000000000020" +
                    "00000000000000000000000000000000000000000000000000000000000000a4" +
                    // `handle(address,address,bytes)` function call to mirror
                    "443ce2a8" +
                    "000000000000000000000000" +
                    safe.address.slice(2).toLowerCase() +
                    "000000000000000000000000" +
                    user1.address.slice(2).toLowerCase() +
                    "0000000000000000000000000000000000000000000000000000000000000060" +
                    "0000000000000000000000000000000000000000000000000000000000000004" +
                    // `0xdededede` selector
                    "dededede" +
                    "0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            );
        });

        it("sends along _msgSender() and _manager() on simple call", async () => {
            const { safe, validator, mirror } = await setupTests();
            await executeContractCallWithSigners(safe, validator, "setDefaultFallbackHandler", [mirror.address], [user1, user2]);

            const tx = {
                to: safe.address,
                data: mirror.interface.encodeFunctionData("lookAtMe"),
            };
            // Check that mock works as handler
            const response = await user1.call(tx);
            expect(response).to.be.eq(
                "0x" +
                    "0000000000000000000000000000000000000000000000000000000000000020" +
                    "000000000000000000000000000000000000000000000000000000000000002c" +
                    // Function call
                    "7f8dc53c" +
                    safe.address.slice(2).toLowerCase() +
                    user1.address.slice(2).toLowerCase() +
                    "0000000000000000000000000000000000000000",
            );
        });

        it("sends along _msgSender() and _manager() on more complex call", async () => {
            const { safe, validator, mirror } = await setupTests();
            await executeContractCallWithSigners(safe, validator, "setDefaultFallbackHandler", [mirror.address], [user1, user2]);

            const tx = {
                to: safe.address,
                data: mirror.interface.encodeFunctionData("nowLookAtYou", [user2.address, "pink<>black"]),
            };
            // Check that mock works as handler
            const response = await user1.call(tx);
            expect(response).to.be.eq(
                "0x" +
                    "0000000000000000000000000000000000000000000000000000000000000020" +
                    "00000000000000000000000000000000000000000000000000000000000000ac" +
                    // Function call
                    "b2a88d99" +
                    "000000000000000000000000" +
                    user2.address.slice(2).toLowerCase() +
                    "0000000000000000000000000000000000000000000000000000000000000040" +
                    "000000000000000000000000000000000000000000000000000000000000000b" +
                    "70696e6b3c3e626c61636b000000000000000000000000000000000000000000" +
                    safe.address.slice(2).toLowerCase() +
                    user1.address.slice(2).toLowerCase() +
                    "0000000000000000000000000000000000000000",
            );
        });
    });
});
