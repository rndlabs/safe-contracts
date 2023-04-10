module.exports = {
    skipFiles: ["test/Token.sol", "test/ERC20Token.sol", "test/TestHandler.sol", "test/TestExtensibleDefaultHandler.sol", "test/ERC1155Token.sol", "test/TestSafeSignatureVerifier.sol"],
    mocha: {
        grep: "@skip-on-coverage", // Find everything with this tag
        invert: true, // Run the grep's inverse set.
    },
};
