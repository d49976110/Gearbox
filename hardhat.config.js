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
