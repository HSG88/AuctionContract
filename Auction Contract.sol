pragma solidity ^0.4.18;
contract Pedersen {
    uint public q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    uint public gX = 19823850254741169819033785099293761935467223354323761392354670518001715552183;
    uint public gY = 15097907474011103550430959168661954736283086276546887690628027914974507414020;
    uint public hX = 3184834430741071145030522771540763108892281233703148152311693391954704539228;
    uint public hY = 1405615944858121891163559530323310827496899969303520166098610312148921359100;
    function Commit(uint b, uint r) public returns (uint cX, uint cY) {
        var (cX1, cY1) = ecMul(b, gX, gY);
        var (cX2, cY2) = ecMul(r, hX, hY);
        (cX, cY) = ecAdd(cX1, cY1, cX2, cY2);
    }
    function Verify(uint b, uint r, uint cX, uint cY) public returns (bool) {
        var (cX2, cY2) = Commit(b,r);
        return cX == cX2 && cY == cY2;
    }
    function CommitDelta(uint cX1, uint cY1, uint cX2, uint cY2) public returns (uint cX, uint cY) {
        (cX, cY) = ecAdd(cX1, cY1, cX2, q-cY2); 
    }
    function ecMul(uint b, uint cX1, uint cY1) private returns (uint cX2, uint cY2) {
        bool success = false;
        bytes memory input = new bytes(96);
        bytes memory output = new bytes(64);
        assembly {
            mstore(add(input, 32), cX1)
            mstore(add(input, 64), cY1)
            mstore(add(input, 96), b)
            success := call(gas(), 7, 0, add(input, 32), 96, add(output, 32), 64)
            cX2 := mload(add(output, 32))
            cY2 := mload(add(output, 64))
        }
        require(success);
    }
    function ecAdd(uint cX1, uint cY1, uint cX2, uint cY2) public returns (uint cX3, uint cY3) {
        bool success = false;
        bytes memory input = new bytes(128);
        bytes memory output = new bytes(64);
        assembly {
            mstore(add(input, 32), cX1)
            mstore(add(input, 64), cY1)
            mstore(add(input, 96), cX2)
            mstore(add(input, 128), cY2)
            success := call(gas(), 6, 0, add(input, 32), 128, add(output, 32), 64)
            cX3 := mload(add(output, 32))
            cY3 := mload(add(output, 64))
        }
        require(success);
    }
}
contract Auction {
    enum VerificationStates {Init, Challenge, Verify, ValidWinner}
    struct ZKPCommit {
        uint cW1X;
        uint cW1Y;
        uint cW2X;
        uint cW2Y;
    }
    struct ZKPResponse {
        uint W1;
        uint R1;
        uint W2;
        uint R2;
        uint M;
        uint N;
        uint J;
    }
    struct Bidder {
        uint commitX;
        uint commitY;
        bytes cipher;
        bool validProof;
        bool paidBack;
        bool existing;
    }
    Pedersen pedersen;
    bool withdrawLock;
    VerificationStates public states;
    address private challengedBidder;
    uint private challengeBlockNumber;
    uint private K = 10;
    uint public V = 5472060717959818805561601436314318772174077789324455915672259473661306552145;
    ZKPCommit[] public zkpCommits;
    ZKPCommit[] public zkpDeltaCommits;
    ZKPResponse public response;
    mapping(address => Bidder) public bidders;
    address[] public indexs;
    //Auction Parameters
    address public auctioneerAddress;
    uint    public bidBlockNumber;
    uint    public revealBlockNumber;
    uint    public winnerPaymentBlockNumber;
    uint    public maxBiddersCount;
    uint    public fairnessFees;
    string  public auctioneerRSAPublicKey; 
    //these values are set when the auctioneer determines the winner
    address public winner;
    uint public highestBid;    
    //Constructor = Setting all Parameters and auctioneerAddress as well
    function Auction(uint _bidBlockNumber, uint _revealBlockNumber, uint _winnerPaymentBlockNumber, uint _maxBiddersCount, uint _fairnessFees, string _auctioneerRSAPublicKey, address pedersenAddress, uint k) public {
        auctioneerAddress = msg.sender;
        bidBlockNumber = block.number + _bidBlockNumber;
        revealBlockNumber = bidBlockNumber + _revealBlockNumber;
        winnerPaymentBlockNumber = revealBlockNumber + _winnerPaymentBlockNumber;
        maxBiddersCount = _maxBiddersCount;
        fairnessFees = _fairnessFees;
        auctioneerRSAPublicKey = _auctioneerRSAPublicKey;  
        pedersen = Pedersen(pedersenAddress);
        K= k;
    }
    function Bid(uint cX, uint cY) public payable {
        require(block.number < bidBlockNumber);   //during bidding Interval  
        require(indexs.length < maxBiddersCount); //available slot    
        require(msg.value >= fairnessFees);  //paying fees
        require(bidders[msg.sender].existing == false);
        bidders[msg.sender] = Bidder(cX, cY, "",false, false,true);
        indexs.push(msg.sender);
    }
    function Reveal(bytes cipher) public {
        require(block.number < revealBlockNumber && block.number > bidBlockNumber);
        require(bidders[msg.sender].existing ==true); //existing bidder
        bidders[msg.sender].cipher = cipher;
    }
    function ClaimWinner(address _winner, uint _bid, uint _r) public challengeByAuctioneer {
        require(states == VerificationStates.Init);
        require(bidders[_winner].existing == true); //existing bidder
        require(_bid < V); //valid bid
        require(pedersen.Verify(_bid, _r, bidders[_winner].commitX, bidders[_winner].commitY)); //valid open of winner's commit        
        winner = _winner;
        highestBid = _bid;
        bidders[winner].validProof = true;
        states = VerificationStates.Challenge;
    }
    function ZKPChallenge(address y, uint[] commits, uint[] deltaCommits) public challengeByAuctioneer {
        require(states == VerificationStates.Challenge);
        require(bidders[y].existing == true); //existing bidder
        challengedBidder = y;
        challengeBlockNumber = block.number;
        for(uint i=0; i< K; i++) {
            zkpCommits.push(ZKPCommit(commits[4*i], commits[4*i+1], commits[4*i+2], commits[4*i+3]));
            zkpDeltaCommits.push(ZKPCommit(deltaCommits[4*i], deltaCommits[4*i+1], deltaCommits[4*i+2], deltaCommits[4*i+3]));
        }
    }
    
    function ZKPVerify(uint[] responses, uint[] deltaResponses) public challengeByAuctioneer {
        uint hash = uint(block.blockhash(challengeBlockNumber));
        uint mask = 1;
        //Verify Bids ZKP
        for(uint i = 0; i<K; i++) {
            response = ZKPResponse(responses[i*7],responses[i*7+1],responses[i*7+2],responses[i*7+3],responses[i*7+4],responses[i*7+5], responses[i*7+6] );
            if((hash & mask<<i) == 0) 
                VerifyCase1(false,i);
            else 
                VerifyCase2(false, bidders[challengedBidder].commitX, bidders[challengedBidder].commitY, i);
        }
        //Verify Delta ZKP
        for(i = 0; i<K; i++) {
            response = ZKPResponse(deltaResponses[i*7],deltaResponses[i*7+1],deltaResponses[i*7+2],deltaResponses[i*7+3],deltaResponses[i*7+4],deltaResponses[i*7+5], deltaResponses[i*7+6] );
            if((hash & mask<<(i+K)) == 0) 
                require(VerifyCase1(true, i));
            else {
                var (cX, cY) = pedersen.CommitDelta(bidders[winner].commitX, bidders[winner].commitY, bidders[challengedBidder].commitX, bidders[challengedBidder].commitY);
                require(VerifyCase2(true, cX, cY, i));
            }
        }
        bidders[challengedBidder].validProof = true;
    }
    function VerifyAll() public challengeByAuctioneer {
        for (uint i = 0; i<indexs.length; i++) 
            require(bidders[indexs[i]].validProof);
        states = VerificationStates.ValidWinner;
    }
    function VerifyCase1(bool delta, uint i) private returns (bool){
        require(V == response.W1 - response.W2);
        ZKPCommit storage commit = zkpCommits[i];
        if(delta)
            commit = zkpDeltaCommits[i];
        require(pedersen.Verify(response.W1, response.R1, commit.cW1X, commit.cW1Y));
        require(pedersen.Verify(response.W2, response.R2, commit.cW2X, commit.cW2Y));
        return true;
    }
    function VerifyCase2(bool delta, uint cX, uint cY, uint i) private returns (bool){
        ZKPCommit storage commit= zkpCommits[i];
        if(delta)
            commit = zkpDeltaCommits[i];
        var (cXW1, cXW2) = pedersen.ecAdd(cX, cY, commit.cW1X, commit.cW1Y);
        if(response.J == 2) 
            (cXW1, cXW2) = pedersen.ecAdd(cX, cY, commit.cW2X, commit.cW2Y);
        require(pedersen.Verify(response.M, response.N, cXW1, cXW2));
        return true;
    }
    function Withdraw() public {
        require(states == VerificationStates.ValidWinner || block.number>winnerPaymentBlockNumber);
        require(msg.sender != winner);
        require(bidders[msg.sender].paidBack == false && bidders[msg.sender].existing == true);
        require(withdrawLock == false);
        withdrawLock = true;
        msg.sender.transfer(fairnessFees);
        bidders[msg.sender].paidBack = true;
        withdrawLock = false;
    }
    function WinnerPay() public payable {
        require(states == VerificationStates.ValidWinner);
        require(msg.sender == winner);
        require(msg.value >= highestBid - fairnessFees);
    }
    function Destroy() public {
        selfdestruct(auctioneerAddress);
    }
    modifier challengeByAuctioneer() {
        require(msg.sender == auctioneerAddress); //by auctioneer only
        //require(block.number > revealBlockNumber && block.number < winnerPaymentBlockNumber); //after reveal and before winner payment
        _;
    }
}