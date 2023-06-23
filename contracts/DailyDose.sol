// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract DailyDose is ERC1155, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;

    uint256 private constant TOTAL_TOKENS = 8;
    uint256 private constant TIER_SIZE = TOTAL_TOKENS / 4;
    uint256 private constant PILL_0 = 0;
    uint256 private constant TIME_PERIOD = 1 minutes; // Change to 24 hours for production
    uint256 private constant MAX_MINTS_PER_WALLET = 3;
    

    uint256 private totalMintedPill0;
    uint256 public saleStartTime;
    uint256 public prizePool;
    uint256 private remainingPill0 = TOTAL_TOKENS;
    uint256 public gameStartTime;
    

    

    Counters.Counter private pillCounter;
    mapping(uint256 => uint256) public pillStartTime;
    mapping(address => uint256) private mintedPill0Count;
    mapping(uint256 => uint256) public minterCountInPeriod;
    mapping(uint256 => string) private _tokenURIs;
    mapping (address => bool) public mintedPill0Addresses;
    mapping (address => bool) public winningAddresses;


    event PillMinted(address indexed user, uint256 indexed pillNumber);
    event AttemptedPillMint(address indexed user, uint256 indexed currentPill, uint256 indexed nextPill);
    event PrizeClaimed(address indexed user, uint256 indexed pillNumber, uint256 amount);
    event updateBaseURI(string uri);


    address payable ownerWallet; 
    uint256 ownerRoyaltyPercentage = 5;
    uint256 prizePoolRoyaltyPercentage = 3;



    constructor() ERC1155("") {
        saleStartTime = 0;
        gameStartTime = 0;
        ownerWallet = payable(msg.sender);

    }


    function setBaseURI(string calldata _uri) external onlyOwner {
        _setURI(_uri);

        emit updateBaseURI(_uri);
    }

    function uri(uint256 tokenid) public view override returns (string memory) {

        require(saleStartTime > 0, "Sale has not started yet");

        if (gameStartTime == 0){
            require(tokenid == 0, "URI query for nonexistent token");

        }

        require(tokenid <= ((block.timestamp - gameStartTime) / TIME_PERIOD)+1, "URI query for nonexistent token");

        string memory baseUri = super.uri(0);
        return string(abi.encodePacked(baseUri, Strings.toString(tokenid), ".json"));
    } 

    // Function to start the sale
    function startSale() public onlyOwner {
        require(saleStartTime == 0, "Sale has already started");
        saleStartTime = block.timestamp;
    }
    // Function to mint initial pills
    function mintPill0(uint256 amount) public payable nonReentrant{

        require(saleStartTime != 0, "Pill 0 sale has not started yet");
        require(block.timestamp >= saleStartTime, "Pill 0 is not available for purchase yet");
        require(remainingPill0 > 0, "Pill 0 is sold out");
        require(amount > 0 && amount <= remainingPill0, "Invalid amount");
        require(mintedPill0Count[msg.sender] + amount <= MAX_MINTS_PER_WALLET, "Exceeds maximum mints per wallet");
        require(gameStartTime==0, "Game has already begun");

        uint256 cost = 0;
        for (uint256 i = 0; i < amount; i++) {
            cost += getTierPrice(1);
            remainingPill0--;
        }

        require(msg.value >= cost, "Payment is not enough");
        
        if (msg.value > cost) {
            uint256 refund = msg.value - cost;
            (bool success, ) = msg.sender.call{value: refund}("");
            require(success, "Refund failed");
        }

        prizePool += cost;
        mintedPill0Count[msg.sender] += amount;
        mintedPill0Addresses[msg.sender] = true;
        _mint(msg.sender, PILL_0, amount, "");
        totalMintedPill0 += amount;
    }

    function pill0MintedCount() public view returns (uint256) {
        return TOTAL_TOKENS - remainingPill0;
    }

    // Function to check mint price of N tokens
    function getTierPrice(uint256 amount) public view returns (uint256) {
        require(amount <= remainingPill0, "Requested amount exceeds the remaining tokens");

        uint256 cost = 0;
        uint256 remainingAmount = amount;
        uint256 remainingInCurrentTier;
        uint256 remainingPill0Copy = remainingPill0;

        //Don't know how this works but it does
        for (uint256 tier = 1; tier <= 4; tier++) {
            if (remainingPill0Copy > (4-tier)*TIER_SIZE) {
                remainingInCurrentTier = remainingPill0Copy - (4-tier)*TIER_SIZE;
            } else {
                remainingInCurrentTier = 0;
            }

            if (remainingAmount > 0) {
                uint256 amountInCurrentTier = remainingAmount > remainingInCurrentTier ? remainingInCurrentTier : remainingAmount;
                cost += amountInCurrentTier * tier * 0.01 ether;
                remainingAmount -= amountInCurrentTier;
                remainingPill0Copy -= amountInCurrentTier;
            }
        }

        return cost;
    }

    // Function to mint all following pills
    function mintNextPill(uint256 amount) public nonReentrant{
        require(gameStartTime > 0, "The game has not started yet");

        uint256 currentPill = (block.timestamp - gameStartTime) / TIME_PERIOD;
        uint256 nextPill = currentPill + 1;

        require(balanceOf(msg.sender, currentPill) >= amount, "You don't have enough of the current pill");
        require(block.timestamp >= gameStartTime + currentPill * TIME_PERIOD, "Next pill is not available yet");

        emit AttemptedPillMint(msg.sender, currentPill, nextPill);

        _burn(msg.sender, currentPill, amount);
        _mint(msg.sender, nextPill, amount, "");

        minterCountInPeriod[currentPill] += amount;
        emit PillMinted(msg.sender, nextPill);
    }


    // Function to start the game
    function startGame() public onlyOwner {
        require(totalMintedPill0 > 0, "At least one Pill 0 must be minted before starting the game");
        require(gameStartTime == 0, "Game has already been started");
        gameStartTime = block.timestamp;
    }

    // Function to claim the reward
    function claimReward() public nonReentrant{
        uint256 currentPill = (block.timestamp - gameStartTime) / TIME_PERIOD;

        // Check that the game has started
        require(gameStartTime > 0, "The game has not started yet");

        // Check that we aren't still in the first day
        require(currentPill > 0, "Be patient, we're just getting started");

        if(minterCountInPeriod[currentPill-1] == 0) {
            // Search backwards until we find a day with a minterCountInPeriod less than 2
            while(minterCountInPeriod[currentPill-1] == 0) {
                currentPill--;
            }
        }

        // Check if yesterdays pill was only minted once
        if(minterCountInPeriod[currentPill-1] == 1) {
            require(balanceOf(msg.sender, currentPill) > 0, "You don't have the winning pill");

            // Burn the winning pill
            _burn(msg.sender, currentPill, 1);

            // Transfer the prize pool to the winner
            uint256 prizeAmount = prizePool;
            prizePool = 0;

            (bool success, ) = msg.sender.call{value: prizeAmount}("");
            require(success, "Prize transfer failed");

            emit PrizeClaimed(msg.sender, currentPill, prizeAmount);

            // Mint a special NFT for the winner
            winningAddresses[msg.sender] = true;
            // _mint(msg.sender, WINNER_NFT_ID, 1, "");

        } else if(minterCountInPeriod[currentPill-1] > 1) {
            require(balanceOf(msg.sender, currentPill) > 0, "You don't have a winning pill from the eligible day");

            // Calculate the prize for each winner
            uint256 prizeAmount = prizePool / minterCountInPeriod[currentPill-1];

            // Burn the winning pill
            _burn(msg.sender, currentPill, 1);

            // Transfer the prize to the winner
            (bool success, ) = msg.sender.call{value: prizeAmount}("");
            require(success, "Prize transfer failed");

            emit PrizeClaimed(msg.sender, currentPill, prizeAmount);
            
            // Mint a special NFT for the winner
            winningAddresses[msg.sender] = true;
            // _mint(msg.sender, WINNER_NFT_ID, 1, "");

            // After all winners have claimed their prizes, reset the prize pool
            if(minterCountInPeriod[currentPill-1] == 0) {
                prizePool = 0;
            }
        }
    }

    // Royalties 
    function royaltyInfo(uint256 _salePrice) external view returns (address receiver, uint256 royaltyAmount) {
        // Total royalty (for owner + prize pool) is calculated here
        uint256 totalRoyalty = (_salePrice * (ownerRoyaltyPercentage + prizePoolRoyaltyPercentage)) / 100;
        return (address(this), totalRoyalty);
    }

    receive() external payable {
        // We calculate the part of the royalty that should go to the prize pool
        uint256 prizePoolPart = (msg.value * prizePoolRoyaltyPercentage) / (ownerRoyaltyPercentage + prizePoolRoyaltyPercentage);
        prizePool += prizePoolPart;

        // The rest goes to the owner's wallet
        uint256 ownerPart = msg.value - prizePoolPart;
        ownerWallet.transfer(ownerPart);
    }




}