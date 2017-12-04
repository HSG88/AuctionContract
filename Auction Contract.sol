pragma solidity ^0.4.18;
contract Pedersen { 
    //uint public q =  21888242871839275222246405745257275088548364400416034343698204186575808495617;
    uint private q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    uint private gX = 19823850254741169819033785099293761935467223354323761392354670518001715552183;
    uint private gY = 15097907474011103550430959168661954736283086276546887690628027914974507414020;
    uint private hX = 3184834430741071145030522771540763108892281233703148152311693391954704539228;
    uint private hY = 1405615944858121891163559530323310827496899969303520166098610312148921359100;
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
        bool validProofs;
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
    uint public Q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
    uint public V = 5472060717959818805561601436314318772174077789324455915672259473661306552145;
    uint[] commits;
    uint[] deltaCommits;
    mapping(address => Bidder) public bidders;
    address[] public indexs;
    uint mask =1;
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
    function Auction(uint _bidBlockNumber, uint _revealBlockNumber, uint _winnerPaymentBlockNumber, uint _maxBiddersCount, uint _fairnessFees, string _auctioneerRSAPublicKey, address pedersenAddress, uint8 k, bool _testing) public payable {
        require(msg.value >= _fairnessFees);
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
        bidders[msg.sender] = Bidder(cX, cY,"", false, false,true);
        indexs.push(msg.sender);
    }
    function Reveal(bytes cipher) public {
        require(block.number < revealBlockNumber && block.number > bidBlockNumber || testing);
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
        states = VerificationStates.Challenge;
    }
    function ZKPCommit(address y, uint[] _commits, uint[] _deltaCommits) public challengeByAuctioneer {
        require(states == VerificationStates.Challenge || testing);
        require(_commits.length == K *4);
        require(_commits.length == _deltaCommits.length);
        require(bidders[y].existing == true); //existing bidder
        challengedBidder = y;
        challengeBlockNumber = block.number;
        for(uint i=0; i< _commits.length; i++)
            if(commits.length == i) {
                commits.push(_commits[i]);
                deltaCommits.push(_deltaCommits[i]);
            } else {
                commits[i] = _commits[i];
                deltaCommits[i] = _deltaCommits[i];
            }
        states = VerificationStates.Verify;
    }
    
    function ZKPVerify(uint[] response, uint[] deltaResponses) public challengeByAuctioneer {
        require(states == VerificationStates.Verify || states == VerificationStates.VerifyDelta);
        uint8 count =0;
        uint hash = uint(block.blockhash(challengeBlockNumber));
        mask =1;
        uint i=0;
        uint j=0;
        uint cX;
        uint cY;
        while(i<response.length && j<commits.length) {
            if(hash&mask == 0) {
                require((response[i] + response[i+2])%Q==V);
                require(pedersen.Verify(response[i], response[i+1], commits[j], commits[j+1]));
                require(pedersen.Verify(response[i+2], response[i+3], commits[j+2], commits[j+3]));
                i+=4;
            } else {
                if(response[i+2] ==1) //z=1
                    (cX, cY) = pedersen.ecAdd(bidders[challengedBidder].commitX, bidders[challengedBidder].commitY, commits[j], commits[j+1]);
                else
                    (cX, cY) = pedersen.ecAdd(bidders[challengedBidder].commitX, bidders[challengedBidder].commitY, commits[j+2], commits[j+3]);
                require(pedersen.Verify(response[i], response[i+1], cX, cY));
                i+=3;
            }
            j+=4;
            mask = mask <<1;
            count++;
        }
        require(count==K);
        count =0;
        i =0;
        j=0;
        while(i<deltaResponses.length && j<deltaCommits.length) {
            
            if(hash&mask == 0) {
                require((deltaResponses[i] + deltaResponses[i+2])%Q==V);
                require(pedersen.Verify(deltaResponses[i], deltaResponses[i+1], deltaCommits[j], deltaCommits[j+1]));
                require(pedersen.Verify(deltaResponses[i+2], deltaResponses[i+3], deltaCommits[j+2], deltaCommits[j+3]));
                i+=4;
            } else {
            (cX, cY) = pedersen.CommitDelta(bidders[winner].commitX, bidders[winner].commitY, bidders[challengedBidder].commitX, bidders[challengedBidder].commitY);
            if(deltaResponses[i+2]==1) 
                (cX, cY) = pedersen.ecAdd(cX,cY, deltaCommits[j], deltaCommits[j+1]);
            else
                (cX, cY) = pedersen.ecAdd(cX,cY, deltaCommits[j+2], deltaCommits[j+3]);
            require(pedersen.Verify(deltaResponses[i],deltaResponses[i+1],cX,cY));
            i+=3;
            }
            j+=4;
            mask = mask <<1;
            count++;
        }
        require(count==K);
        bidders[challengedBidder].validProofs = true;
        states = VerificationStates.Challenge;
    }
    function VerifyAll() public challengeByAuctioneer {
        for (uint i = 0; i<indexs.length; i++) 
                if(indexs[i] != winner)
                    if(!bidders[indexs[i]].validProofs) {
                        winner = 0;
                        revert();
                    }
                        
        states = VerificationStates.ValidWinner;
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
        require(block.number > revealBlockNumber && block.number < winnerPaymentBlockNumber || testing); //after reveal and before winner payment
        _;
    }
}