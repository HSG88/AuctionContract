using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
using System.Text;
using System.Threading.Tasks;

namespace Auctioneer
{
    class Program
    {
        static int bidFees = 1;                 //Fairness initial deposit in Ethers
        static int biddingInterval = 10;        //number of blocks after the deployment to the end of Bidding phase
        static int revealInterval = 10;         //Block interval after the Bidding phase to the end of Revealing phase 
        static int verificationInterval = 100;  //Block interval for verifiying the correctness of proofs
        static int K = 10;                      //Number of rounds for ZKP protocol
        static  bool testing = true;            //To bypass the intervals check for faster testing, this code doesn't support false
        static void Main(string[] args)
        {
            Console.WriteLine("Auction Contract Test Program");
            AuctionContract contract = new AuctionContract(bidFees, biddingInterval, revealInterval, verificationInterval,K, testing);
            contract.Test().Wait();
            Console.WriteLine("Auction is complete");
            Console.ReadLine();
        }
    }
}
