import { buildContractSignature } from "./../../../src/utils/execution";
import { expect } from "chai";
import hre, { deployments, waffle, ethers } from "hardhat";
import "@nomiclabs/hardhat-ethers";
import { deployContract, getExtensibleFallbackHandler, getSafeWithOwners, getSignatureVerifierMuxer } from "../../utils/setup";
import {
    buildSignatureBytes,
    executeContractCallWithSigners,
    calculateSafeMessageHash,
    preimageSafeMessageHash,
    EIP712_SAFE_MESSAGE_TYPE,
    signHash,
} from "../../../src/utils/execution";
import { chainId } from "../../utils/encoding";

describe("SignatureVerifierMuxer", async () => {
    const [user1, user2] = waffle.provider.getWallets();

    const setupTests = deployments.createFixture(async ({ deployments }) => {
        await deployments.fixture();
        const TestVerifier = await hre.ethers.getContractFactory("TestSafeSignatureVerifier");
        const verifier = await TestVerifier.deploy();
        const handler = await getExtensibleFallbackHandler();
        const signLib = await (await hre.ethers.getContractFactory("SignMessageLib")).deploy();
        const signerSafe = await getSafeWithOwners([user1.address], 1, handler.address);
        const safe = await getSafeWithOwners([user1.address, user2.address, signerSafe.address], 2, handler.address);
        const muxer = await getSignatureVerifierMuxer();

        // Set the SignatureVerifierMuxer as the default handler for isValidSignature(bytes32,bytes) calls
        await executeContractCallWithSigners(
            safe,
            handler.attach(safe.address),
            "setSafeMethod",
            ["0x1626ba7e", muxer.address],
            [user1, user2],
        );

        const erc1271source = `
        contract ERC1271 {
            function isValidSignature(bytes32 _hash, bytes memory _signature) public view returns (bytes4 magicValue) {
                return bytes4(0x00000000);
            }
        }`;

        const erc1271 = await deployContract(user1, erc1271source);
        const validator = erc1271.attach(safe.address);

        return {
            safe,
            validator,
            handler,
            signLib,
            signerSafe,
            muxer,
            verifier,
        };
    });

    describe("setDomainVerifier(bytes32,address)", async () => {
        it("emits added / changed / removed events", async () => {
            const { safe, muxer, verifier } = await setupTests();
            const domainHash = ethers.utils.keccak256("0xdeadbeef");

            // added event
            await expect(executeContractCallWithSigners(safe, muxer, "setDomainVerifier", [domainHash, verifier.address], [user1, user2]))
                .to.emit(muxer, "AddedDomainVerifier")
                .withArgs(safe.address, domainHash, verifier.address);

            // changed event
            await expect(executeContractCallWithSigners(safe, muxer, "setDomainVerifier", [domainHash, user2.address], [user1, user2]))
                .to.emit(muxer, "ChangedDomainVerifier")
                .withArgs(safe.address, domainHash, verifier.address, user2.address);

            // removed event
            await expect(
                executeContractCallWithSigners(
                    safe,
                    muxer,
                    "setDomainVerifier",
                    [domainHash, ethers.constants.AddressZero],
                    [user1, user2],
                ),
            )
                .to.emit(muxer, "RemovedDomainVerifier")
                .withArgs(safe.address, domainHash);
        });
    });

    describe("handle(address,address,bytes)", async () => {
        it("should revert for non isValidSignature calls", async () => {
            const { muxer } = await setupTests();
            await expect(muxer.callStatic.handle(user1.address, user1.address, "0xdeadbeef")).to.be.revertedWith("Invalid selector");
        });
    });

    describe("isValidSignature(bytes32,bytes)", async () => {
        describe("Domain specific implementation", async () => {
            it("should override the default implementation", async () => {
                const { safe, muxer, verifier, validator } = await setupTests();
                const domainHash = ethers.utils.keccak256("0xdeadbeef");

                const message = "0xbaddadbaddadbaddadbaddadbaddadbaddad";
                const dataHash = ethers.utils.keccak256(message);

                const shouldBeValidSig = {
                    to: safe.address,
                    data:
                        validator.interface.encodeFunctionData("isValidSignature(bytes32,bytes)", [dataHash, message]) +
                        domainHash.slice(2),
                };

                const shouldBeInvalidSig = {
                    to: safe.address,
                    data:
                        validator.interface.encodeFunctionData("isValidSignature(bytes32,bytes)", [dataHash, dataHash]) +
                        domainHash.slice(2),
                };

                // As the default implementation is what's set, this should revert with `GS020`
                await expect(user1.call(shouldBeValidSig)).to.be.revertedWith("GS020");

                // Set the domain specific implementation
                await executeContractCallWithSigners(safe, muxer, "setDomainVerifier", [domainHash, verifier.address], [user1, user2]);

                // This should now succeed
                expect(
                    validator.interface.decodeFunctionResult("isValidSignature(bytes32,bytes)", await user1.call(shouldBeValidSig))[0],
                ).to.be.eq("0x1626ba7e");

                // This should return 0x00000000
                expect(
                    validator.interface.decodeFunctionResult("isValidSignature(bytes32,bytes)", await user1.call(shouldBeInvalidSig))[0],
                ).to.be.eq("0x00000000");
            });
        });
        describe("Default implementation", async () => {
            it("should revert if called directly", async () => {
                const { validator, muxer } = await setupTests();
                const dataHash = ethers.utils.keccak256("0xbaddad");

                const muxerValidator = validator.attach(muxer.address);

                // this should revert because the muxer does not have a fallback function
                // and doesn't implement the isValidSignature(bytes32,bytes) method
                await expect(muxerValidator.callStatic["isValidSignature(bytes32,bytes)"](dataHash, "0x")).to.be.revertedWith(
                    "function selector was not recognized and there's no fallback function",
                );
            });

            it("should revert if message was not signed", async () => {
                const { validator } = await setupTests();
                const dataHash = ethers.utils.keccak256("0xbaddad");
                await expect(validator.callStatic["isValidSignature(bytes32,bytes)"](dataHash, "0x")).to.be.revertedWith(
                    "Hash not approved",
                );
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
});
