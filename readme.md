# Verifiable Sealed-bid Auction on Ethereum Blockchain

This is the accompanying code for the article "Verifiable Sealed-bid Auction on Ethereum Blockchain". It consists of:

 * Two Solidity contracts: Auction and Pedersen
 * C# Console application for interaction with these contracts

### Setup a Private Blockchain
1. Install Ethereum client [Geth](https://geth.ethereum.org/downloads/) 1.7.3 or higher.
2. Create a new directory on your drive to contain the private blockchain
3. Copy the *genesis.json* file to that directory
4. Open cmd/powershell/terminal and switch to the directory
5. Execute `geth --datadir <directory_name> init genesis.json`
6. Execute ```geth --datadir <directory_name> --networkid 300 --rpc --rpcaddr "127.0.0.1" --port "8545" --rpccorsdomain "*" --rpcapi "eth,net,web3,admin,personal" console ```

Now your private blockchain is ready and it supports Byzantium added proposals. We need a set of accounts to act as bidders and auctioneer.
1. Execute ```personal.newAccount('123')``` to create new account with password *123*.
2. After creating multiple accounts, we need to start mining some ethers on each account.
```
miner.setEtherbase(eth.accounts[0])
miner.start(4)
...
miner.stop()
```
3.Repeat the above commands but with different indexs 1, 2, ...

 ### Testing the contracts
 1. Build the C# project using Visual Studio 2017
 2. Start the miner on geth console
 3. Run the application and it will report a sequence of transactions starting from the deployment to finalizing the auction.
 4. Happy testing.

### Modifying the contracts
 1. Edit the contracts on [Remix](https://ethereum.github.io/browser-solidity)
 2. Click on details and copy ABI and BIN to the associated files under Contracts subdirectory
 3. Build the code and run it to test the new changes.
