using Nethereum.ABI.FunctionEncoding.Attributes;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Numerics;
using System.Text;
using System.Threading.Tasks;

namespace Auctioneer
{
    [FunctionOutput]
    class Bidder
    {
        [Parameter("uint", "commitX", 1)]
        public BigInteger CommitX { set; get; }
        [Parameter("uint", "commitY", 1)]
        public BigInteger CommitY { set; get; }
        [Parameter("bytes", "cipher", 2)]
        public byte[] Cipher { set; get; }
        [Parameter("bool", "validProof", 4)]
        public bool ValidProof { set; get; }
        [Parameter("bool", "existing", 5)]
        public bool Existing { set; get; }
        [Parameter("bool", "paidBack", 6)]
        public bool PaidBack { set; get; }
        public string Address { get; set; }
        public BigInteger Bid { get; set; }
        public BigInteger Random { get; set; }
        
    }
    [FunctionOutput]
    class Commit
    {
        [Parameter("uint", 1)]
        public BigInteger X { set; get; }
        [Parameter("uint", 2)]
        public BigInteger Y { set; get; }
    }
    class eventDTO
    {
        [Parameter("string", "a", 1, true)]
        public string msg { set; get; }
    }
}
