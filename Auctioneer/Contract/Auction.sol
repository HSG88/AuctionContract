pragma solidity ^0.4.18;
contract Auction {
    bool withdrawLock;
    enum VerificationStates {Invalid, Start, ChallengeBid, ChallengeDifference, Completed, WinnerPaid}
    VerificationStates public states;
    bytes public g = hex"2bd3e6d0f3b142924f5ca7b49ce5b9d54c4703d7ae5648e61d02268b1a0a9fb721611ce0a6af85915e2f1d70300909ce2e49dfad4a4619c8390cae66cefdb204";
    bytes public h = hex"070a8d6a982153cae4be29d434e8faef8a47b274a053f5a4ee2a6c9c13c31e5c031b8ce914eba3a9ffb989f9cdd5b0f01943074bf4f0f315690ec3cec6981afc";
    bytes public p = hex"30644E72E131A029B85045B68181585D97816A916871CA8D3C208C16D87CFD47";
    uint public pp;
    struct Bidder {
        bytes commit;
        bytes cipher;
        bytes difference;
        bool validCommit;
        bool validDifference;
        bool paidBack;
    }
    struct ZKPCommit {
        address bidder;
        uint blockNumber;
        bytes cW1;
        bytes cW2;
    }
    ZKPCommit zkpCommit;
    mapping(address => Bidder) public bidders;
    address[] public indexs;
    //Auction Parameters
    address public auctioneerAddress;
    uint    public bidBlockNumber;
    uint    public revealBlockNumber;
    uint    public winnerPaymentBlockNumber;
    uint    public maxBiddersCount;
    uint    public registerationFees;
    uint    public maximumBidValue;
    string  public auctioneerRSAPublicKey; 
    //these values are set when the auctioneer determines the winner
    address public winner;
    uint public highestBid;    
    //Constructor = Setting all Parameters and auctioneerAddress as well
    function Auction(uint _bidBlockNumber, uint _revealBlockNumber, uint _winnerPaymentBlockNumber, uint _maxBiddersCount, uint _registerationFees, string _auctioneerRSAPublicKey) public {
        auctioneerAddress = msg.sender;
        bidBlockNumber = block.number + _bidBlockNumber;
        revealBlockNumber = bidBlockNumber + _revealBlockNumber;
        winnerPaymentBlockNumber = revealBlockNumber + _winnerPaymentBlockNumber;
        maxBiddersCount = _maxBiddersCount;
        registerationFees = _registerationFees;
        auctioneerRSAPublicKey = _auctioneerRSAPublicKey;        
        states = VerificationStates.Invalid;
        maximumBidValue = 1000000; //for testing purpose
        pp = convertBytesToUint(p);
    }
    function commitBid(bytes c) public payable {
        require(c.length == 64); //valid commit size
        require(block.number < bidBlockNumber);   //during bidding Interval  
        require(indexs.length < maxBiddersCount); //available slot    
        if (bidders[msg.sender].commit.length == 0) { // new bidder => add the address
            require(msg.value >= registerationFees);  //paying fees
            indexs.push(msg.sender); 
        }
        bidders[msg.sender] = Bidder(c,"","",false,false,false);
    }
    function revealBid(bytes cipher) public {
        require(block.number < revealBlockNumber && block.number > bidBlockNumber);
        require(bidders[msg.sender].commit.length != 0); //existing bidder
        bidders[msg.sender].cipher = cipher;
    }
    function beginToVerify(address _winner, uint _bid, uint _r) public challengeByAuctioneer {
        require(states == VerificationStates.Invalid);
        require(bidders[_winner].commit.length != 0); //existing bidder
        require(_bid < maximumBidValue); //valid bid
        require(pedersenVerify(_bid, _r, bidders[_winner].commit)); //valid open of winner's commit        
        winner = _winner;
        highestBid = _bid;
        states = VerificationStates.Start;
        createCommitsDifferences();
    }
    function zkpChallenge(address y, bytes cW1, bytes cW2, bool isDiff) public challengeByAuctioneer {
        require(states == VerificationStates.Start);
        require(bidders[y].commit.length != 0); //existing bidder
        zkpCommit = ZKPCommit(y, block.number,cW1,cW2);
        if (isDiff) {
            states = VerificationStates.ChallengeDifference;
        } else {
            states = VerificationStates.ChallengeBid;
        }
    }    
    function zkpVerifyCase1(uint w1, uint r1, uint w2, uint r2) public modVerify {
        require((uint(block.blockhash(zkpCommit.blockNumber))&0x1) == 0); //valid case
        require(maximumBidValue == (w1-w2) || maximumBidValue == (w2-w1));
        require(pedersenVerify(w1, r1, zkpCommit.cW1) && pedersenVerify(w2,r2,zkpCommit.cW2));
        finishVerify();
    }
    function zkpVerifyCase2(uint m, uint n, uint j) public modVerify {
        require((uint(block.blockhash(zkpCommit.blockNumber))&0x1) == 1); //valid case
        bytes memory commitXWj = pedersenCommit(m, n);
        if (states == VerificationStates.ChallengeBid) {
            if (j == 1 ) {
                require(isEqual(commitXWj, ecAdd(bidders[zkpCommit.bidder].commit, zkpCommit.cW1)));
            } else {
                require(isEqual(commitXWj, ecAdd(bidders[zkpCommit.bidder].commit, zkpCommit.cW2)));
            }
        } else {
            if (j == 1 ) {
                require(isEqual(commitXWj, ecAdd(bidders[zkpCommit.bidder].difference, zkpCommit.cW1)));
            } else {
                require(isEqual(commitXWj, ecAdd(bidders[zkpCommit.bidder].difference, zkpCommit.cW2)));
            }
        }
        finishVerify();
    }
    function completeVerification() public challengeByAuctioneer {
        for (uint i = 0; i<indexs.length; i++) {
            if (indexs[i] == winner) {
                continue;
            }
            require(bidders[indexs[i]].validCommit && bidders[indexs[i]].validDifference);
        }
        states = VerificationStates.Completed;
    }
    function withdrawFees() public {
        require(states == VerificationStates.Completed || block.number>winnerPaymentBlockNumber);
        require(msg.sender != winner);
        require(bidders[msg.sender].paidBack == false && bidders[msg.sender].commit.length != 0);
        require(withdrawLock == false);
        withdrawLock = true;
        msg.sender.transfer(registerationFees);
        bidders[msg.sender].paidBack = true;
        withdrawLock = false;
    }
    function winnerPay() public payable {
        require(states == VerificationStates.Completed);
        require(msg.sender == winner);
        require(msg.value >= highestBid - registerationFees);
        states = VerificationStates.WinnerPaid;
    }
    modifier modVerify() {
        require(msg.sender == auctioneerAddress); //by auctioneer only
        require(block.number > revealBlockNumber && block.number < winnerPaymentBlockNumber); //after reveal and before winner payment
        require(states == VerificationStates.ChallengeBid || states == VerificationStates.ChallengeDifference);
        _;
    }
    modifier challengeByAuctioneer() {
        require(msg.sender == auctioneerAddress); //by auctioneer only
        require(block.number > revealBlockNumber && block.number < winnerPaymentBlockNumber); //after reveal and before winner payment
        _;
    }
    function finishVerify() private {
        if (states == VerificationStates.ChallengeBid) {
            bidders[zkpCommit.bidder].validCommit = true;
        } else {
            bidders[zkpCommit.bidder].validDifference = true;
        }
        states = VerificationStates.Start;
    }
    function createCommitsDifferences() private {
        for (uint i = 0; i<indexs.length; i++) {
            if (indexs[i] != winner) {
                bidders[indexs[i]].difference = commitDifference(bidders[winner].commit, bidders[indexs[i]].commit);
            }
        }
    }    
    function pedersenCommit(uint x, uint r) public returns (bytes) {
        return ecAdd(ecMul(g, x), ecMul(h, r));
    }
    function pedersenVerify(uint x, uint r, bytes c) public returns (bool) {
        return isEqual(c, pedersenCommit(x, r));       
    }
    function commitDifference(bytes x, bytes y) private returns (bytes) {
        return ecAdd(x, ecNeg(y));
    }    
    function ecNeg(bytes input) private view returns (bytes) {
        bytes memory output = new bytes(64);
        bytes memory y = new bytes(32);
        assembly{
            mstore(add(y, 32), mload(add(input,64)))
        }
        uint yy = convertBytesToUint(y);
        uint rr = pp - yy;
        assembly{
            mstore(add(output, 32), mload(add(input, 32)))
            mstore(add(output, 64), rr)
        }
        return output;
    }
    function ecMul(bytes x, uint y) private returns (bytes) {
        bool success = false;
        bytes memory input = new bytes(96);
        bytes memory output = new bytes(64);
        assembly {
            mstore(add(input, 32), mload(add(x, 32)))
            mstore(add(input, 64), mload(add(x, 64)))
            mstore(add(input, 96), y)
            success := call(gas(), 7, 0, add(input, 32), 96, add(output, 32), 64)
        }
        require(success);
        return output;

    }
    function ecAdd(bytes x, bytes y) private returns (bytes) {
        bool success = false;
        bytes memory input = new bytes(128);
        bytes memory output = new bytes(64);
        assembly {
            mstore(add(input, 32), mload(add(x, 32)))
            mstore(add(input, 64), mload(add(x, 64)))
            mstore(add(input, 96), mload(add(y, 32)))
            mstore(add(input, 128), mload(add(y, 64)))
            success := call(gas(), 6, 0, add(input, 32), 128, add(output, 32), 64)
        }
        require(success);
        return output;
    }
    function convertBytesToUint(bytes x) private pure returns (uint) {
        uint r;
        assembly{
            r :=mload(add(x,32))
        }
        return r;
    }
    function isEqual(bytes x, bytes y) private pure returns (bool) {
        require(x.length == y.length);
        for (uint i = 0; i<x.length; i++) {
            if (x[i] != y[i]) {
                return false;
            }
        }
        return true;
    }
}