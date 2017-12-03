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
        static void Main(string[] args)
        {
            Console.WriteLine("Auction Contract Test Program");
            AuctionContract contract = new AuctionContract();
            contract.Test().Wait();
            Console.WriteLine("Auction is complete");
            Console.ReadLine();
        }
    }
}
