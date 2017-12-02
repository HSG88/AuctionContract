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
    enum VerificationStates {Init, Challenge,ChallengeDelta, Verify, VerifyDelta, ValidWinner}
    struct Bidder {
        uint commitX;
        uint commitY;
        bytes cipher;
        uint8 validProof;
        uint8 validDelta;
        bool paidBack;
        bool existing;
    }
    Pedersen pedersen;
    bool withdrawLock;
    VerificationStates public states;
    address private challengedBidder;
    uint private challengeBlockNumber;
    bool private testing; //for fast testing without checking block intervals
    uint8 private K = 10; //number of multiple rounds per ZKP 
    uint public V = 5472060717959818805561601436314318772174077789324455915672259473661306552145;
    //W1, R1, W2, R2 per one commit, the next half of the array is for delta commits
    uint[4] public zkpCommits; 
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
    function Auction(uint _bidBlockNumber, uint _revealBlockNumber, uint _winnerPaymentBlockNumber, uint _maxBiddersCount, uint _fairnessFees, string _auctioneerRSAPublicKey, address pedersenAddress, uint8 k, bool _testing) public {
        auctioneerAddress = msg.sender;
        bidBlockNumber = block.number + _bidBlockNumber;
        revealBlockNumber = bidBlockNumber + _revealBlockNumber;
        winnerPaymentBlockNumber = revealBlockNumber + _winnerPaymentBlockNumber;
        maxBiddersCount = _maxBiddersCount;
        fairnessFees = _fairnessFees;
        auctioneerRSAPublicKey = _auctioneerRSAPublicKey;  
        pedersen = Pedersen(pedersenAddress);
        K= k;
        testing = _testing;
    }
    function Bid(uint cX, uint cY) public payable {
        require(block.number < bidBlockNumber || testing);   //during bidding Interval  
        require(indexs.length < maxBiddersCount); //available slot    
        require(msg.value >= fairnessFees);  //paying fees
        require(bidders[msg.sender].existing == false);
        bidders[msg.sender] = Bidder(cX, cY, "",0,0, false,true);
        indexs.push(msg.sender);
    }
    function Reveal(bytes cipher) public {
        require(block.number < revealBlockNumber && block.number > bidBlockNumber || testing);
        require(bidders[msg.sender].existing ==true); //existing bidder
        bidders[msg.sender].cipher = cipher;
    }
    function ClaimWinner(address _winner, uint _bid, uint _r) public challengeByAuctioneer {
        require(states == VerificationStates.Init || testing);
        require(bidders[_winner].existing == true); //existing bidder
        require(_bid < V); //valid bid
        require(pedersen.Verify(_bid, _r, bidders[_winner].commitX, bidders[_winner].commitY)); //valid open of winner's commit        
        winner = _winner;
        highestBid = _bid;
        states = VerificationStates.Challenge;
    }
    function ZKPChallenge(address y, uint[4] commits, bool isDelta) public challengeByAuctioneer {
        require(states == VerificationStates.Challenge || testing);
        require(bidders[y].existing == true); //existing bidder
        challengedBidder = y;
        challengeBlockNumber = block.number;
        for(uint i=0; i< commits.length; i++)
            zkpCommits[i] = commits[i];
        if(isDelta)
            states = VerificationStates.VerifyDelta;
        else
            states = VerificationStates.Verify;
    }
    
    function ZKPVerify1(uint[4] response, bool isDelta) public challengeByAuctioneer {
        require(states == VerificationStates.Verify || states == VerificationStates.VerifyDelta);
        require(block.blockhash(challengeBlockNumber)[0] == 0);
        require(response[0] - response[2] == V);
        require(pedersen.Verify(response[0], response[1], zkpCommits[0], zkpCommits[1]));
        require(pedersen.Verify(response[2], response[3], zkpCommits[2], zkpCommits[3]));
        if(isDelta)
            bidders[challengedBidder].validDelta ++;
        else
            bidders[challengedBidder].validProof ++;
        states = VerificationStates.Challenge;
    }
    function ZKPVerify2(uint[2] response, uint8 j, bool isDelta) public challengeByAuctioneer {
        require(states == VerificationStates.Verify || states == VerificationStates.VerifyDelta);
        require(block.blockhash(challengeBlockNumber)[0] == 0);
        uint cX; uint cY;
        if( isDelta) {
                (cX, cY) = pedersen.CommitDelta(bidders[winner].commitX, bidders[winner].commitY, bidders[challengedBidder].commitX, bidders[challengedBidder].commitY);
            if(j==1) 
                (cX, cY) = pedersen.ecAdd(cX,cY, zkpCommits[0], zkpCommits[1]);
            else
                (cX, cY) = pedersen.ecAdd(cX,cY, zkpCommits[2], zkpCommits[3]);
        } else {
            if(j ==1) 
                (cX, cY) = pedersen.ecAdd(bidders[challengedBidder].commitX, bidders[challengedBidder].commitY, zkpCommits[0], zkpCommits[1]);
            else
                (cX, cY) = pedersen.ecAdd(bidders[challengedBidder].commitX, bidders[challengedBidder].commitY, zkpCommits[2], zkpCommits[3]);
        }
        require(pedersen.Verify(response[0], response[1], cX, cY));
        if(isDelta)
            bidders[challengedBidder].validDelta ++;
        else
            bidders[challengedBidder].validProof ++;
        states = VerificationStates.Challenge;
    }
    function VerifyAll() public challengeByAuctioneer {
        for (uint i = 0; i<indexs.length; i++) 
                if(indexs[i] != winner) {
                    require(bidders[indexs[i]].validProof == K);
                    require(bidders[indexs[i]].validDelta == K);
                }
        states = VerificationStates.ValidWinner;
    }
    function Withdraw() public {
        require(states == VerificationStates.ValidWinner || block.number>winnerPaymentBlockNumber || testing);
        require(msg.sender != winner);
        require(bidders[msg.sender].paidBack == false && bidders[msg.sender].existing == true);
        require(withdrawLock == false);
        withdrawLock = true;
        msg.sender.transfer(fairnessFees);
        bidders[msg.sender].paidBack = true;
        withdrawLock = false;
    }
    function WinnerPay() public payable {
        require(states == VerificationStates.ValidWinner || testing);
        require(msg.sender == winner);
        require(msg.value >= highestBid - fairnessFees);
    }
    function Destroy() public {
        selfdestruct(auctioneerAddress);
    }
    modifier challengeByAuctioneer() {
        require(msg.sender == auctioneerAddress); //by auctioneer only
        require(block.number > revealBlockNumber && block.number < winnerPaymentBlockNumber || testing); //after reveal and before winner payment
        _;
    }
}