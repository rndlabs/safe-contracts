import { buildContractSignature } from "./../../src/utils/execution";
import { expect } from "chai";
import hre, { deployments, waffle, ethers } from "hardhat";
import "@nomiclabs/hardhat-ethers";
import { AddressZero } from "@ethersproject/constants";
import { extensibleFallbackHandlerContract, getCompatFallbackHandler, getExtensibleFallbackHandler, getSafeWithOwners } from "../utils/setup";
import {
    buildSignatureBytes,
    executeContractCallWithSigners,
    calculateSafeMessageHash,
    preimageSafeMessageHash,
    EIP712_SAFE_MESSAGE_TYPE,
    signHash,
} from "../../src/utils/execution";
import { chainId } from "../utils/encoding";
import { BigNumber } from "ethers";
import { killLibContract } from "../utils/contracts";

describe("ExtensibleFallbackHandler", async () => {
    const [user1, user2] = waffle.provider.getWallets();

    const setupTests = deployments.createFixture(async ({ deployments }) => {
        await deployments.fixture();
        const signLib = await (await hre.ethers.getContractFactory("SignMessageLib")).deploy();
        const handler = await getExtensibleFallbackHandler();
        // const signerHandler = await getCompatFallbackHandler();
        const signerSafe = await getSafeWithOwners([user1.address], 1, handler.address);
        const safe = await getSafeWithOwners([user1.address, user2.address, signerSafe.address], 2, handler.address);
        const validator = (await extensibleFallbackHandlerContract()).attach(safe.address);
        const killLib = await killLibContract(user1);
        return {
            safe,
            validator,
            handler,
            killLib,
            signLib,
            signerSafe,
        };
    });

    describe("ERC1155", async () => {
        it("to handle onERC1155Received", async () => {
            const { handler } = await setupTests();
            await expect(await handler.callStatic.onERC1155Received(AddressZero, AddressZero, 0, 0, "0x")).to.be.eq("0xf23a6e61");
        });

        it("to handle onERC1155BatchReceived", async () => {
            const { handler } = await setupTests();
            await expect(await handler.callStatic.onERC1155BatchReceived(AddressZero, AddressZero, [], [], "0x")).to.be.eq("0xbc197c81");
        });
    });

    describe("ERC721", async () => {
        it("to handle onERC721Received", async () => {
            const { handler } = await setupTests();
            await expect(await handler.callStatic.onERC721Received(AddressZero, AddressZero, 0, "0x")).to.be.eq("0x150b7a02");
        });
    });

    describe("isValidSignature(bytes32,bytes)", async () => {
        it("should revert if called directly", async () => {
            const { handler } = await setupTests();
            const dataHash = ethers.utils.keccak256("0xbaddad");
            await expect(handler.callStatic["isValidSignature(bytes32,bytes)"](dataHash, "0x")).to.be.revertedWith(
                "function call to a non-contract account",
            );
        });

        it("should revert if message was not signed", async () => {
            const { validator } = await setupTests();
            const dataHash = ethers.utils.keccak256("0xbaddad");
            await expect(validator.callStatic["isValidSignature(bytes32,bytes)"](dataHash, "0x")).to.be.revertedWith("Hash not approved");
        });

        it("should revert if signature is not valid", async () => {
            const { validator } = await setupTests();
            const dataHash = ethers.utils.keccak256("0xbaddad");
            await expect(validator.callStatic["isValidSignature(bytes32,bytes)"](dataHash, "0xdeaddeaddeaddead")).to.be.reverted;
        });

        it("should return magic value if message was signed", async () => {
            const { safe, validator, signLib } = await setupTests();
            const dataHash = ethers.utils.keccak256("0xbaddad");
            await executeContractCallWithSigners(safe, signLib, "signMessage", [dataHash], [user1, user2], true);
            expect(await validator.callStatic["isValidSignature(bytes32,bytes)"](dataHash, "0x")).to.be.eq("0x1626ba7e");
        });

        it("should return magic value if enough owners signed and allow a mix different signature types", async () => {
            const { validator, signerSafe } = await setupTests();
            const dataHash = ethers.utils.keccak256("0xbaddad");
            const typedDataSig = {
                signer: user1.address,
                data: await user1._signTypedData(
                    { verifyingContract: validator.address, chainId: await chainId() },
                    EIP712_SAFE_MESSAGE_TYPE,
                    { message: dataHash },
                ),
            };
            const ethSignSig = await signHash(user2, calculateSafeMessageHash(validator, dataHash, await chainId()));
            const validatorPreImageMessage = preimageSafeMessageHash(validator, dataHash, await chainId());
            const signerSafeMessageHash = calculateSafeMessageHash(signerSafe, validatorPreImageMessage, await chainId());
            const signerSafeOwnerSignature = await signHash(user1, signerSafeMessageHash);
            const signerSafeSig = buildContractSignature(signerSafe.address, signerSafeOwnerSignature.data);

            expect(
                await validator.callStatic["isValidSignature(bytes32,bytes)"](
                    dataHash,
                    buildSignatureBytes([typedDataSig, ethSignSig, signerSafeSig]),
                ),
            ).to.be.eq("0x1626ba7e");
        });
    });
});
