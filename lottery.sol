// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/** Roadmap
    // - pay => get added to the list
    // - wait x amount of time
    // - close payable
    // - random number select
    // - announce winner
    // - check balance => divide money to receivers (winners, donations, owner)
    // - open winner can claim => start a timer (after timer ends and no claim, donate the money)
    // - let winner choose donate or claim or to next round
    // - donate funds ("public" function after owner can claim)
    // - get ur cut
    // - open the payable and start the timer
*/ 

/** Notes
    // - uint immutable => uint won't change after assign ever.
    // -
    // - Arrange lottery for a decentralized randomizer
    // - Test payables. ownersCut-donation-prizeclaim etc.
*/

/** 
    * Errors
*/

/** 

    /// @notice Sale is either open or not while it shouldn't.
    /// @param 
    error WrongSaleState(bool saleState);

    /// @notice 
    /// @param 
    error WrongDonationState(bool donationState);

    /// @notice 
    /// @param 
    error RandomNumberPicked(bool randomNumberPicked);

    /// @notice Message value is less than ticket price.
    /// @param value msg.value
    error NotEnoughMoneyInput(uint value);

    /// @notice Sender is not the winner.
    /// @param sender msg.sender
    error Unauthorized(address sender);

    /// @notice 
    /// @param 
    error PrizeAlreadyClaimed();

    /// @notice 
    /// @param 
    error PrizeClaimTimePassed();

    /// @notice Owner claimed their share before.
    /// @param ownerClaimed state of ownerClaimed
    error OwnerAlreadyClaimed();
*/


/** 
     * @custom:author  0xWindsor
     * @custom:contributor  0xWindsor
     * 
     */
contract lottery1 is VRFConsumerBaseV2, Ownable {
    
    /// @dev Took from Chainlink VRF and implemented to the contract. Below variables are from the example VRFv2Consumer contract.
    /// @notice
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 s_subscriptionId; // Chainlink VRF subscription ID.
    address vrfCoordinator = 0x6168499c0cFfCaCD319c818142124B7A15E857ab; // Chainlink coordinator.
    bytes32 keyHash = 0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc; // Chainlink keyHash
    uint32 callbackGasLimit = 100000; //
    uint16 requestConfirmations = 3;
    uint32 numWords =  1;
    uint256[] public s_randomWords;
    uint256 public s_requestId;

    uint immutable ticketPrice = 1 wei;

    /// @notice The time until sale ends. (Period of people can buy) 
    uint immutable saleCooldownTime = 10 minutes;
    uint public saleCooldownReadyTime; 

    bool public randomNumberPicked;
    bool public prizeClaimable;
    bool public prizeClaimed;
    bool public donationHasMade;
    bool private ownerClaimed;

    /// @notice PrizeClaimCooldownTime is less than saleCooldownTime.
    /// It's a game-design choice. When the next lottery starts, participants 
    /// will know if the prize is transfered to other round.
    uint immutable prizeClaimCooldownTime = 5 minutes;
    uint public prizeClaimTime; 

    /// @notice The percentages that parties will receive from the prize pool.
    uint immutable prizePercentage = 90;
    uint immutable donationPercentage = 5;
    uint immutable ownersPercentage = 5;

    /// @notice Amounts parties will receive from the prize pool. 
    uint private prizeAmount;
    uint private donationAmount;
    uint private ownersCut;

    // @notice lottery => (index => participants)
    mapping(uint => mapping(uint => address)) public participants;
    address public winner;
    address public donationAddress; /// Donation address may be changed by the owner by the function changeDonationAddress. 

    uint private currentIndex = 0; // Participants register number.
    uint public lotteryNumber = 0; // Using with "participant" and tracks which lottery roll we're in. 

    constructor(uint64 subscriptionId) VRFConsumerBaseV2(vrfCoordinator) {
        COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
        s_subscriptionId = subscriptionId;
    }

    /*////////////////////////////////////////////////
        //            PUBLIC FUNCTIONS          //    
    ////////////////////////////////////////////////*/

    /** 
     * @notice Adds msg.sender to participants list if gets paid enough. 
     * @notice No money refund if paid too much, becareful.
     */
    function buyTicket(uint _amount) public payable {
        require(_saleIsOpen(), "WrongSaleState"); // Check if the sale is still open.
        require(msg.value >= ticketPrice, "NotEnoughMoneyInput");
        
        participants[lotteryNumber][currentIndex] = msg.sender;
        currentIndex += _amount;
    }

    /** 
     * 
     * 
     */
    function lottery() public {
            require(!_saleIsOpen(), "WrongSaleState");
            require(!randomNumberPicked, "RandomNumberPicked");

            requestRandomWords();
    }

    /** 
     * @notice Lets winner to choose from claim, donate or to keep prize to other round.
     * @param _claim If wanted to claim the prize or not.
     * @param _donate If not claimed, donate the prize or not.
     */
    function claimPrize(bool _claim, bool _donate) public {
        require(msg.sender == winner, "Unauthorized");
        require(prizeClaimable, "PrizeAlreadyClaimed"); // Prize isn't claimed before.
        require(uint(block.timestamp) <= prizeClaimTime, "PrizeClaimTimePassed"); // 

        if(_claim) {
            payable(msg.sender).transfer(prizeAmount);
        }
        // If not claimed, donate or not.
        if(!_claim && _donate) {
            payable(donationAddress).transfer(prizeAmount);
        }

        // If both not claimed and not donated, do nothing.
        // In every case, if function is called, close claimable. 
        prizeClaimable = false;
    }

    /** 
     * 
     * 
     */
    function donate() public {
        require(randomNumberPicked, "RandomNumberNotPicked");
        require(!donationHasMade, "WrongDonationState");
        payable(donationAddress).transfer(donationAmount);
        donationHasMade = true;
    }

    /** 
     * 
     * 
     */
    function ownerClaim() public {
        require(donationHasMade, "WrongDonationState"); // To this should be true, first the number must be picked. So we check it there. 
        require(!ownerClaimed, "OwnerAlreadyClaimed");
        payable(owner()).transfer(ownersCut);
        ownerClaimed = true;
        _startSale();
    }

    /** 
     * 
     * 
     */
    function changeDonationAddress(address _newDonationAddress) public onlyOwner {
        require(_saleIsOpen(), "WrongSaleState");
        donationAddress = _newDonationAddress;
    }


    /*////////////////////////////////////////////////
        //              VIEW FUNCTIONS          //      
    ////////////////////////////////////////////////*/

    function soldTickets() public view returns(uint) {
        return(currentIndex - 1);
    }

    function seeMoneyPool() public view returns(uint) {
        return(address(this).balance);
    }

    function seePrizeAmount() public view returns(uint) {
        return(address(this).balance * prizePercentage);
    }


    /*////////////////////////////////////////////////
        //          INTERNAL FUNCTIONS          //    
    ////////////////////////////////////////////////*/

    /// @dev Chainlink VRF function.
    /// @dev Proceeds with fullfilRandomWords function which gets called by ChainlinkVRF.
    function requestRandomWords() internal {
        // Will revert if subscription is not set and funded.
        s_requestId = COORDINATOR.requestRandomWords(
        keyHash,
        s_subscriptionId,
        requestConfirmations,
        callbackGasLimit,
        numWords
        );
    }

    /// @dev Called by ChainlinkVRF after calling requestRandomWords.
    /// @dev Completes lottery function.
    function fulfillRandomWords(
    uint256, /* requestId */
    uint256[] memory randomWords
    ) internal override {
        s_randomWords = randomWords;


        uint _randomNumber = (s_randomWords[0] % currentIndex - 1);
        winner = participants[lotteryNumber][_randomNumber];
        if(winner == address(0x0)) {
                do {
                    _randomNumber--;
                    winner = participants[lotteryNumber][_randomNumber];
                } while(winner == address(0x0));
        }

        randomNumberPicked = true;

        _dividePrize();

        prizeClaimable = true;
        prizeClaimTime = prizeClaimCooldownTime + block.timestamp;
    }

    /** 
     * @notice Divides current prize pool to pieces.
     */
    function _dividePrize() internal {
            uint _dividableAmount = uint(address(this).balance);

            prizeAmount = _dividableAmount * prizePercentage / 100;
            donationAmount = _dividableAmount * donationPercentage / 100;
            ownersCut = _dividableAmount * ownersPercentage / 100;
    }

    /** 
     * 
     * 
     */
    function _startSale() internal {
            require(!_saleIsOpen(), "SaleIsOpen"); /// Check if the sale is still going. 
            saleCooldownReadyTime = uint(block.timestamp + saleCooldownTime); /// If sale's not going, set when it'll end.
            randomNumberPicked = false; 
            prizeClaimable = false;
            donationHasMade = false;

            /** 
             * We can set this to false cuz if owner wants to 
             * claim, the donation should've been made. But
             * we've set it to false above, so we're safe.
             */
            ownerClaimed = false; 
            lotteryNumber++; /// Reset participants.
    }

    /** 
     * 
     * 
     */
    function _saleIsOpen() internal view returns(bool) {
        // block is on 0001.
        // sCRT is set to 0005.
        // until it's 0005 people can buy.
        return(uint(block.timestamp) <= saleCooldownReadyTime);
    }
}

/**

    The time until sale ends. (Period of people can buy) 

    PrizeClaimCooldownTime is less than saleCooldownTime. It's a game-design choice. When the next lottery starts, participants will know if the prize is transfered to other round.

    The percentages that parties will receive from the prize pool.

    Amounts parties will receive from the prize pool. 

    Donation address may be changed by the owner by the function changeDonationAddress.

    Participants register number.

    Using with "participant" and tracks which lottery roll we're in.

    Adds msg.sender to participants list if gets paid enough.

    No money refund if paid too much, becareful.

    Check if the sale is still open.

    Lets winner to choose from claim, donate or to keep prize to other round.

    If wanted to claim the prize or not.

    If not claimed, donate the prize or not.

    Prize isn't claimed before.

    If not claimed, donate or not.

    If both not claimed and not donated, do nothing.

    In every case, if function is called, close claimable.

    To this should be true, first the number must be picked. So we check it there.

    Divides current prize pool to pieces.

    Check if the sale is still going. 

    If sale's not going, set when it'll end.

    We can set this to false cuz if owner wants to claim, the donation should've been made. But we've set it to false above, so we're safe.

 */
