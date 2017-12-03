using Nethereum.Contracts;
using Nethereum.Hex.HexTypes;
using Nethereum.RPC.Eth.DTOs;
using Nethereum.Web3;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Numerics;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;

namespace Auctioneer
{
    class AuctionContract
    {
        RandomNumberGenerator RNG;
        BigInteger Q = BigInteger.Parse("21888242871839275222246405745257275088696311157297823662689037894645226208583");
        BigInteger maxBid;        
        public string[] Accounts { get; private set; }//0= auctioneer, then bidder1, bidder2, bidder3
        List<Bidder> bidders;
        int bidFees = 1, bidding = 10, reveal = 10, payment = 100, count = 10, winnerIndex, K=10;
        bool testing = true;
        Contract auctionContract, pedersenContract;
        Web3 web3;
        RSACryptoServiceProvider rsa = new RSACryptoServiceProvider();
        Function Bid, Reveal, ClaimWinner, ZKPCommit, ZKPVerify, VerifyAll, WinnerPay, Withdraw, Commit, Verify, BiddersMap;
        public AuctionContract()
        {
            RNG = RandomNumberGenerator.Create();
            maxBid = Q / 4;
            web3 = new Web3("http://127.0.0.1:8545/");
            bidders = new List<Bidder>();
        }
        private async Task DeployPedersenContract()
        {
            var abi = File.ReadAllText("Contract\\abiPedersen.txt");
            var bin = File.ReadAllText("Contract\\binPedersen.txt");
            Accounts = (await web3.Personal.ListAccounts.SendRequestAsync());
            await web3.Personal.UnlockAccount.SendRequestAsync(Accounts[0], "123", 120);
            TransactionReceipt receipt = await web3.Eth.DeployContract.SendRequestAndWaitForReceiptAsync(abi, bin, Accounts[0], new HexBigInteger(300000000), null);
            pedersenContract = web3.Eth.GetContract(abi, receipt.ContractAddress);
            Commit = pedersenContract.GetFunction(nameof(Commit));
            Verify = pedersenContract.GetFunction(nameof(Verify));
            Console.WriteLine("Deployed Pedersen contract, Gas = " + receipt.GasUsed.Value);
        }
        private async Task DeployAuctionContract()
        {
            var abi = File.ReadAllText("Contract\\abiAuction.txt");
            var bin = File.ReadAllText("Contract\\binAuction.txt");
            count = Accounts.Length - 1;
            object[] parameters = new object[] { new BigInteger(bidding), new BigInteger(reveal), new BigInteger(payment), new BigInteger(count), bidFees * BigInteger.Parse("1000000000000000000"), rsa.ToXmlString(false), pedersenContract.Address, K, testing };
            TransactionReceipt receipt = await web3.Eth.DeployContract.SendRequestAndWaitForReceiptAsync(abi, bin, Accounts[0], new HexBigInteger(300000000), null, new HexBigInteger(bidFees * BigInteger.Parse("1000000000000000000")), null, parameters);
            auctionContract = web3.Eth.GetContract(abi, receipt.ContractAddress);
            Bid = auctionContract.GetFunction(nameof(Bid));
            Reveal = auctionContract.GetFunction(nameof(Reveal));
            ClaimWinner = auctionContract.GetFunction(nameof(ClaimWinner));
            ZKPCommit = auctionContract.GetFunction(nameof(ZKPCommit));
            ZKPVerify = auctionContract.GetFunction(nameof(ZKPVerify));
            VerifyAll = auctionContract.GetFunction(nameof(VerifyAll));
            Withdraw = auctionContract.GetFunction(nameof(Withdraw));
            WinnerPay = auctionContract.GetFunction(nameof(WinnerPay));
            BiddersMap = auctionContract.GetFunction("bidders");
            Console.WriteLine("Deployed Auction contract, Gas = " + receipt.GasUsed.Value+"\nAddress = "+auctionContract.Address);
            if (testing)
                return;
            var b = receipt.BlockNumber.Value + bidding;
            var r = b + reveal;
            var p = r + payment;
            Console.WriteLine(string.Format("Bidding ends at block {0}\r\nRevealing ends at block {1}\r\nPayment ends at block {2}", b, r, p));
        }
        public async Task Test()
        {
            await DeployPedersenContract();
            await DeployAuctionContract();
            await CreateBidders();
            await StartBid();
            await StartReveal();
            await StartDecrypt();
            await StartClaimWinner();
            await Prove();
            await StartVerifyAll();
            await RefundHonest();
        }
        private BigInteger GetRandom(bool big=false)
        {
            byte[] r;
            if (big)
                r = new byte[10];
            else
                r = new byte[5];
            RNG.GetBytes(r, 0, r.Length - 1);
            return new BigInteger(r);
        }
        private byte[] Encrypt(BigInteger bid, BigInteger random)
        {
            byte[] data = new byte[64];
            byte[] temp = bid.ToByteArray();
            Array.Copy(temp, data, temp.Length);
            temp = random.ToByteArray();
            Array.Copy(temp, 0, data, 32, temp.Length);
            return rsa.Encrypt(data, true);
        }
        private async Task CreateBidders()
        {
            Console.WriteLine("\nCreating Bidders");
            for (int i = 1; i < Accounts.Length; i++)
            {
                Bidder x = new Bidder();
                x.Address = Accounts[i];
                x.Bid = GetRandom();
                x.Random = GetRandom();               
                var commit = await Commit.CallDeserializingToObjectAsync<Commit>(x.Bid, x.Random);
                x.CommitX = commit.X;
                x.CommitY = commit.Y;
                x.Cipher = Encrypt(x.Bid, x.Random);
                bidders.Add(x);
                Console.WriteLine(string.Format("Bidder = {0}\nBid = {1}\nRandom = {2}",x.Address,x.Bid,x.Random));
            }
        }
        private async Task StartBid()
        {
            Console.WriteLine("\nStart Bidding Phase");
            foreach(var bidder in bidders)
            {
                await web3.Personal.UnlockAccount.SendRequestAsync(bidder.Address, "123", 120);
                var receipt = await Bid.SendTransactionAndWaitForReceiptAsync(bidder.Address, new HexBigInteger(300000000), null, new HexBigInteger(bidFees * BigInteger.Parse("1000000000000000000")), null, bidder.CommitX, bidder.CommitY);
                Debug.Assert(receipt.Status.Value == 1);
                Console.WriteLine(string.Format("Bidder = {0}\nCommitX = {1}\nCommitY = {2}\nGas = {3}", bidder.Address, bidder.CommitX, bidder.CommitY, receipt.GasUsed.Value), false);
            }
            Console.WriteLine("Bidding Phase ended\n");
        }
        private async Task StartReveal()
        {
            Console.WriteLine("Start Revealing Phase");
            foreach (var bidder in bidders)
            {
                await web3.Personal.UnlockAccount.SendRequestAsync(bidder.Address, "123", 120);
                var receipt = await Reveal.SendTransactionAndWaitForReceiptAsync(bidder.Address, new HexBigInteger(300000000), null, null, null, bidder.Cipher);
                Debug.Assert(receipt.Status.Value == 1);
                Console.WriteLine(string.Format("Reveal Bidder {0}\nGas = {1}", bidder.Address, receipt.GasUsed.Value), false);
            }
            Console.WriteLine("Revealing Phase ended\n");
        }
        private async Task StartDecrypt()
        {
            for (int i = 1; i < Accounts.Length; i++)
            {
                Console.WriteLine("Decrypting cipher of Bidder {0}", Accounts[i]);
                var x = await BiddersMap.CallDeserializingToObjectAsync<Bidder>(Accounts[i]);
                byte[] data = rsa.Decrypt(x.Cipher, true);
                byte[] xx = new byte[32];
                byte[] yy = new byte[32];
                Array.Copy(data, xx, 32);
                Array.Copy(data, 32, yy, 0, 32);
                x.Address = Accounts[i];
                x.Bid = new BigInteger(xx);
                x.Random = new BigInteger(yy);
                bidders.Single(y => y.Address == x.Address && y.Bid == x.Bid && y.Random == x.Random);
            }
        }
        private async Task StartClaimWinner()
        {
            winnerIndex = 0;
            for (int i = 1; i < bidders.Count; i++)
            {
                if (bidders[i].Bid > bidders[winnerIndex].Bid)
                    winnerIndex = i;
            }
            var x = bidders[winnerIndex];
            await web3.Personal.UnlockAccount.SendRequestAsync(Accounts[0], "123", 120);
            var receipt = await ClaimWinner.SendTransactionAndWaitForReceiptAsync(Accounts[0], new HexBigInteger(30000000000), null, null, null, x.Address, x.Bid, x.Random);
            Debug.Assert(receipt.Status.Value == 1);
            Console.WriteLine(string.Format("\nClaimWinner Bidder = {0}\nBid = {1}\nGas = {2}\n", x.Address, x.Bid, receipt.GasUsed.Value));
        }
        private async Task Prove()
        {
            for (int i = 0; i < bidders.Count; i++)
            {
                if (i == winnerIndex)
                    continue;
                await Challenge(bidders[i]);
            }
           Console.WriteLine("All verifications are completed successfully");
        }
        private  void GenerateChallenges(out List<BigInteger> commits, out List<BigInteger> opens)
        {
            commits = new List<BigInteger>();
            opens = new List<BigInteger>();
            for (int i = 0; i < K; i++)
            {
                var w1 = GetRandom(true);
                var w2 = Q - (w1 - maxBid);
                var r1 = GetRandom(true);
                var r2 = GetRandom(true);
                var cW1 = Commit.CallDeserializingToObjectAsync<Commit>(w1, r1).Result;
                var cW2 = Commit.CallDeserializingToObjectAsync<Commit>(w2, r2).Result;
                commits.AddRange(new BigInteger[] { cW1.X, cW1.Y, cW2.X, cW2.Y });
                opens.AddRange(new BigInteger[] { w1, r1, w2, r2 });
            }
        }
        private async Task Challenge(Bidder x)
        {
            await web3.Personal.UnlockAccount.SendRequestAsync(Accounts[0], "123", 120);
            List<BigInteger> commits, opens, deltaCommits, deltaOpens;
            List<BigInteger> responses = new List<BigInteger>();
            List<BigInteger> deltaResponses = new List<BigInteger>();
            GenerateChallenges(out commits, out opens);
            GenerateChallenges(out deltaCommits, out deltaOpens);
            var receipt = await ZKPCommit.SendTransactionAndWaitForReceiptAsync(Accounts[0], new HexBigInteger(30000000000), null, null, null, x.Address, commits, deltaCommits);
            Debug.Assert(receipt.Status.Value == 1);
            Console.WriteLine("ZKPCommit Bidder = " + x.Address + "\nGas = " + receipt.GasUsed.Value);

            string cc = receipt.BlockHash.Substring(2);
            BigInteger challenge = BigInteger.Parse("00"+ cc, System.Globalization.NumberStyles.AllowHexSpecifier);
            BigInteger mask = 1;
            for(int i=0,j=0; i< K;i++, j+=4)
            {
                if ((challenge & mask) == 0)
                    responses.AddRange(new BigInteger[] { opens[j], opens[j + 1], opens[j + 2], opens[j + 3] });
                else
                {
                    var m = opens[j] + x.Bid;
                    var n = opens[j + 1] + x.Random;
                    var z = 1;
                    if (m > maxBid || m < 0)
                    {
                        z = 2;
                        m = opens[j+ 2] + x.Bid;
                        n = opens[j+ 3] + x.Random;
                    }
                    responses.AddRange(new BigInteger[] { m, n, z });
                }
                mask = mask << 1;
            }
            for (int i = 0, j = 0; i < K; i++, j += 4)
            {
                if((challenge & mask) == 0)
                {
                    deltaResponses.AddRange(new BigInteger[] { deltaOpens[j], deltaOpens[j+ 1], deltaOpens[j + 2], deltaOpens[j+ 3]});
                }
                else
                {
                    var m = deltaOpens[j] + bidders[winnerIndex].Bid - x.Bid;
                    var n = deltaOpens[j+ 1] + bidders[winnerIndex].Random - x.Random;
                    var z = 1;
                    if (m > maxBid || m < 0)
                    {
                        z = 2;
                        m = deltaOpens[j + 2] + bidders[winnerIndex].Bid - x.Bid;
                        n = deltaOpens[j + 3] + bidders[winnerIndex].Random - x.Random;
                    }
                    if (n < 0)
                        n += Q;
                    deltaResponses.AddRange(new BigInteger[] {  m, n, z });
                }
                mask = mask << 1;
            }
            await web3.Personal.UnlockAccount.SendRequestAsync(Accounts[0], "123", 120);
            receipt = await ZKPVerify.SendTransactionAndWaitForReceiptAsync(Accounts[0], new HexBigInteger(30000000000), null, null, null, responses, deltaResponses);
            Console.WriteLine("ZKPVerify succeeded with Gas = " + receipt.GasUsed.Value+"\tStatus = "+receipt.Status.Value);
        }     
        private async Task StartVerifyAll()
        {
            await web3.Personal.UnlockAccount.SendRequestAsync(Accounts[0], "123", 120);
            var receipt = await VerifyAll.SendTransactionAndWaitForReceiptAsync(Accounts[0], new HexBigInteger(30000000000), null, null);
            Console.WriteLine(string.Format("VerifyAll succeeded\nGas = {0}\tStatus = {1}\n", receipt.GasUsed.Value, receipt.Status.Value));
        }
        private async Task RefundHonest()
        {
            for (int i=0; i< bidders.Count; i++)
            {
                if (i == winnerIndex)
                    continue;
                await web3.Personal.UnlockAccount.SendRequestAsync(bidders[i].Address, "123", 120);
                var receipt = await Withdraw.SendTransactionAndWaitForReceiptAsync(bidders[i].Address, new HexBigInteger(30000000000),new HexBigInteger(20),null,null,null);
                Console.WriteLine(string.Format("Refunding Bidder = {0}\nGas = {1}", bidders[i].Address, receipt.GasUsed.Value), false);
            }
        }
    }
}
