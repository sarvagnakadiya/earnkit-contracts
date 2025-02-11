# test
```shell
forge test -vvvv
```

# deploy campaing
```shell
chmod +x script/deploy-campaign.sh
./script/deploy-campaign.sh
```
take the deployed address of campaign contract and set it in .env as CAMPAIGN_CONTRACT_ADDRESS
then deploy earnkit by running the following command


before deploying 
check the contract address for uniswap
switch mainnet/sepolia properly
# deploy earnkit & LpLocker
```shell
chmod +x script/deploy.sh
./script/deploy.sh
```

# Deploy a token with campaign
```shell
chmod +x script/deploy-token-with-campaign.sh
./script/deploy-token-with-campaign.sh
```


Deployed addresses Base Sepolia
- campaign contract: [0x61ffA02c609078512901508ceC6D1E54D88dF0C1](https://sepolia.basescan.org/address/0x61ffA02c609078512901508ceC6D1E54D88dF0C1)
- ProtocolRewards: [0xfD828F95a9060655b4B7894050Ec32C406eb1451](https://sepolia.basescan.org/address/0xfD828F95a9060655b4B7894050Ec32C406eb1451)
- earnkit: [0xdAa5AF55de378ff182fA1dE3923A475E0529608F](https://sepolia.basescan.org/address/0xdaa5af55de378ff182fa1de3923a475e0529608f)
- LpLocker: [0xd638626b95d4Fe5cd0eC8D580485029D422333Ff](https://sepolia.basescan.org/address/0xd638626b95d4Fe5cd0eC8D580485029D422333Ff)

Deployed addresses Base Mainnet
- campaign contract: [0xf482f26F43459186a8E17A08a2FbBDf07C7aBc66](https://basescan.org/address/0xf482f26F43459186a8E17A08a2FbBDf07C7aBc66)
- ProtocolRewards: [0x9532e26Aa56D76cA1acdCaC36F5fc58685baf201](https://basescan.org/address/0x9532e26Aa56D76cA1acdCaC36F5fc58685baf201)
- earnkit: [0xDF29E0CE7fE906065608fef642dA4Dc4169f924b](https://basescan.org/address/0xDF29E0CE7fE906065608fef642dA4Dc4169f924b)
- LpLocker: [0x5DC3D35bE02F3BF3E152bc5DeFd449ec37e6237F](https://basescan.org/address/0x5DC3D35bE02F3BF3E152bc5DeFd449ec37e6237F)


## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

```shell
forge script script/Deploy.s.sol --rpc-url $RPC_URL -vvvv --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```
