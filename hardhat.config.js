require("@nomiclabs/hardhat-waffle");

module.exports = {
    solidity: {
        compilers: [
            {
                version: "0.8.17",
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
            {
                version: "0.7.4",
            },
            {
                version: "0.5.16",
            },
        ],
    },
};
