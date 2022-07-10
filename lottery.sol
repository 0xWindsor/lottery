// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/access/Ownable.sol";

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
    // - Arrange lottery for a decentralized randomizer
    // - Look for donation address. Maybe put it into 
    // - Test payables. ownersCut-donation-prizeclaim etc.
    // - Import onlyOwner
    // - look for "delete participants"
    // - look for percantage * for ownersPercentage etc.
*/

/** 
     * 
     * 
     */
contract lottery1 is Ownable {



    uint ticketPrice = 1 wei;

    /// @notice The time until sale ends. (Period of people can buy) 
    uint saleCooldownTime = 30 days;
    uint saleCooldownReadyTime; 

    bool randomNumberPicked;
    bool prizeClaimable;
    bool prizeClaimed;
    bool donationHasMade;
    bool ownerClaimed;

    /// @notice PrizeClaimCooldownTime is less than saleCooldownTime.
    /// It's a game-design choice. When the next lottery starts, participants 
    /// will know if the prize is transfered to other round.
    uint prizeClaimCooldownTime = 15 days;
    uint prizeClaimTime; 

    /// @notice The percentages that parties will receive from the prize pool.
    uint prizePercentage = 90;
    uint donationPercentage = 5;
    uint ownersPercentage = 5;

    /// @notice Amounts parties will receive from the prize pool. 
    uint prizeAmount;
    uint donationAmount;
    uint ownersCut;

    address[] participants;
    address winner;
    address donationAddress; /// Donation address may be changed by the owner by the function changeDonationAddress. 


    /*////////////////////////////////////////////////
        //            PUBLIC FUNCTIONS          //    
    ////////////////////////////////////////////////*/

    /** 
     * @notice Adds msg.sender to participants list if gets paid enough. 
     * @notice No money refund if paid too much, becareful.
     */
    function buyTicket() public payable {
            require(_saleIsOpen()); // Check if the sale is still open.
            require(msg.value >= ticketPrice);

            participants.push(msg.sender);
    }

    /** 
     * 
     * 
     */
    function lottery() public {
            require(!_saleIsOpen());
            require(!randomNumberPicked);

            uint _randomNumber = _getRandomNumber();
            winner = participants[_randomNumber];
            randomNumberPicked = true;

            _dividePrize();

            prizeClaimable = true;
            prizeClaimTime = prizeClaimCooldownTime + block.timestamp;
    }

    /** 
     * @notice Lets winner to choose from claim, donate or to keep prize to other round.
     * @param _claim If wanted to claim the prize or not.
     * @param _donate If not claimed, donate the prize or not.
     */
    function claimPrize(bool _claim, bool _donate) public {
        require(msg.sender == winner);
        require(prizeClaimable); // Prize isn't claimed before.
        require(uint(block.timestamp) <= prizeClaimTime); // 

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
        require(randomNumberPicked);
        require(!donationHasMade);
        payable(donationAddress).transfer(donationAmount);
        donationHasMade = true;
    }

    /** 
     * 
     * 
     */
    function ownerClaim() public {
        require(donationHasMade); // To this should be true, first the number must be picked. So we check it there. 
        require(!ownerClaimed);
        payable(owner()).transfer(ownersCut);
        ownerClaimed = true;
        _startSale();
    }

    /** 
     * 
     * 
     */
    function changeDonationAddress(address _newDonationAddress) public onlyOwner {
        require(_saleIsOpen());
        donationAddress = _newDonationAddress;
    }


    /*////////////////////////////////////////////////
        //              VIEW FUNCTIONS          //      
    ////////////////////////////////////////////////*/

    function soldTickets() public view returns(uint) {
        return(participants.length);
    }

    function prizePool() public view returns(uint) {
        return(address(this).balance);
    }

    function seePrizeAmount() public view returns(uint) {
        return(address(this).balance * prizePercentage);
    }

    function seeWinner() public view returns(address) {
        return(winner);
    }

    function seeDonationAddress() public view returns(address) {
        return(donationAddress);
    }

    /*////////////////////////////////////////////////
        //          INTERNAL FUNCTIONS          //    
    ////////////////////////////////////////////////*/


    /** 
     * 
     * 
     */
    function _getRandomNumber() internal view returns(uint) {
            return(uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp % participants.length))));
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
            require(!_saleIsOpen()); /// Check if the sale is still going. 
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
            delete participants; /// Reset participants.
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

