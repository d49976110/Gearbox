require("@nomiclabs/hardhat-waffle");
require("dotenv").config();

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
                version: "0.6.0",
            },
        ],
    },
    networks: {
        hardhat: {
            forking: {
                url: process.env.JSON_RPC_URL,
                blockNumber: 16146300,
            },
            allowUnlimitedContractSize: true,
        },
    },
};
