// SPDX-License-Identifier: MIT

/*** Proudly Developed By: Jaafar Krayem ***/

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IVestingContract {
    function setVestingSchedule(
        uint256 _saleID,
        address _beneficiary,
        uint256 _totalAmount,
        uint256 _startDate,
        uint256 _lockPeriod,
        uint256 _percentageLock,
        uint256 _interval
    ) external;

    function releaseVestedTokens(address _beneficiary) external;
}

contract VaccineToken is ERC20 {
    IVestingContract public vestingContract;

    IERC20 usdtToken;

    uint256 private buyerId;
    uint256 public saleID;

    address public deadWallet = 0x000000000000000000000000000000000000dEaD;

    address public owner;
    address public saleReceiver;

    uint256 public price;
    uint256 public minAmount = 100;
    uint256 public maxAmount = 10000;
    uint256 public referralPercentage = 5; // default is 5%

    bool paused = true;
    bool saleStarted = false;

    struct SaleRound {
        uint256 duration;
        uint256 tokens;
        uint256 price;
        uint256 lockPeriod;
        uint256 releasePercentage;
        string releaseSchedule;
    }

    struct buyerData {
        uint256 buyerID;
        uint256 buyerAmount;
        mapping(string => uint256) roundPercentage;
        uint256 totalBuyPercentage;
        uint256 airdropReceived;
        uint256 totalPaid;
    }

    mapping(address => buyerData) public buyerDetails;
    mapping(string => SaleRound) public rounds;
    mapping(address => uint256) public airdropReceived;

    mapping(address => bool) public Whitelist; //used for private sale and all sales before dex or cex
    mapping(address => bool) public isBuyer;
    mapping(address => bool) public isReferral;
    mapping(string => uint256) public roundTokens;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not Owner");
        _;
    }

    modifier isWhitelist() {
        require(Whitelist[msg.sender], "Not Whitelisted");
        _;
    }

    modifier notPaused() {
        require(paused != true, "Sale is paused!");
        _;
    }

    modifier minMax(uint256 _amount) {
        require(_amount >= minAmount, "Less the minimum");
        require(_amount <= maxAmount, "Above maximum");
        _;
    }

    address[] public buyers;

    event changeOwner(address indexed Owner, address indexed newOwner);
    event renounceOwnerShip(address indexed Owner, address indexed newOwner);
    event buyTokens(
        string round,
        address buyer,
        uint256 tokenAmount,
        uint256 paidToken,
        uint256 price
    );

    constructor() ERC20("Vaccine", "VAC") {
        _mint(msg.sender, 7400000000 * (1e18));
        _mint(address(this), 2600000000 * (1e18));
    }

    function startSaleRounds() external onlyOwner{
        require(!saleStarted, "Sale rounds started already!");
        rounds["Private Sale Round 1"] = SaleRound(
            180 days + block.timestamp,
            500000000 * (1e18),
            6 * (1e15),
            24,
            10,
            "10% first month, 5% monthly after linearly"
        );
        roundTokens["Private Sale Round 1"] = 500000000 * (1e18);
        rounds["Private Sale Round 2"] = SaleRound(
            180 days + block.timestamp,
            500000000 * (1e18),
            8 * (1e15),
            18,
            10,
            "10% first month, 5% monthly after linearly"
        );
        roundTokens["Private Sale Round 2"] = 500000000 * (1e18);
        rounds["Public Sale Round 1"] = SaleRound(
            90 days + block.timestamp,
            600000000 * (1e18),
            1 * (1e16),
            0,
            20,
            "10% monthly after linearly"
        );
        roundTokens["Public Sale Round 1"] = 600000000 * (1e18);
        rounds["Airdrop Round 1"] = SaleRound(
            0,
            60000000 * (1e18),
            0,
            0,
            100,
            "AirDrop 1"
        );
        rounds["Public Sale Round 2"] = SaleRound(
            30 days + block.timestamp,
            500000000 * (1e18),
            15 * (1e15),
            0,
            30,
            "10% monthly after linearly"
        );
        roundTokens["Public Sale Round 2"] = 500000000 * (1e18);
        rounds["Airdrop Round 2"] = SaleRound(
            0,
            30000000 * (1e18),
            0,
            0,
            100,
            "AirDrop 2"
        );
        rounds["Public Sale Round 3"] = SaleRound(
            0,
            400000000 * (1e18),
            2 * (1e16),
            0,
            40,
            "10% monthly after linearly"
        );
        roundTokens["Public Sale Round 3"] = 400000000 * (1e18);
        rounds["Airdrop Round 3"] = SaleRound(
            0,
            10000000 * (1e18),
            0,
            0,
            100,
            "AirDrop 3"
        );
        paused = false;
        saleStarted = true;
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "address zero");
        emit changeOwner(owner, _newOwner);
        owner = _newOwner;
    }

    function renounceOwner(bool _confirm) external onlyOwner {
        if (_confirm == true) {
            emit renounceOwnerShip(owner, address(0x0));
            owner = address(0x0);
        }
    }

    function togglePause(bool _status) external onlyOwner {
        paused = _status;
    }

    function setMinMax(uint256 _min, uint256 _max) external onlyOwner {
        require(_min != 0 && _max != 0, "can't be zero");
        minAmount = _min * (1e18);
        maxAmount = _max * (1e18);
    }

    function addReferral(address _referral) external onlyOwner {
        require(_referral != address(0), "Zero address cannot be a referral");
        isReferral[_referral] = true;
    }

    function setReferralPercentage(uint256 _newPercentage) external onlyOwner {
        require(
            _newPercentage >= 0 && _newPercentage <= 100,
            "Invalid percentage"
        );
        referralPercentage = _newPercentage;
    }

    function getRoundDetails(string memory _roundName)
        public
        view
        returns (SaleRound memory)
    {
        return rounds[_roundName];
    }

    function buy(uint256 usdtAmount, address referral)
        external
        notPaused
        isWhitelist
        minMax(usdtAmount)
    {
        (
            string memory currentRound,
            string memory previousRound
        ) = getCurrentAndPreviousRound();

        // Check if the previous round has ended and transfer remaining tokens to the dead wallet
        transferRemainingTokensToDeadWallet(previousRound);

        SaleRound memory roundDetails = rounds[currentRound];

        uint256 referralAmount = 0;
        uint256 saleAmount = usdtAmount;
        uint256 _saleAmount = usdtAmount;

        // Check if the referral is valid
        if (referral != address(0) && isReferral[referral]) {
            referralAmount = (usdtAmount * referralPercentage) / 100;
            saleAmount = usdtAmount - referralAmount;
        }

        uint256 tokenAmount = (usdtAmount / roundDetails.price) * (1e18);
        require(
            tokenAmount <= roundDetails.tokens,
            "Not enough tokens left in this round"
        );

        // Transfer USDT from user to this contract
        IERC20(usdtToken).transferFrom(msg.sender, address(this), usdtAmount);

        saleID++; 

        // Transfer to saleReceiver
        IERC20(usdtToken).transfer(saleReceiver, saleAmount);

        // Transfer to referral if applicable
        if (referralAmount > 0) {
            IERC20(usdtToken).transfer(referral, referralAmount);
        }

        uint256 _roundPercentage = ((tokenAmount * (1e2)) /
            roundTokens[currentRound]) * 100;

        // Update buyerData
        buyerDetails[msg.sender].buyerAmount += tokenAmount;
        buyerDetails[msg.sender].roundPercentage[
            currentRound
        ] += _roundPercentage;
        buyerDetails[msg.sender].totalBuyPercentage += _roundPercentage;
        buyerDetails[msg.sender].totalPaid += usdtAmount;

        uint256 lockPercentage = 100 - roundDetails.releasePercentage;
        uint256 releaseAmount = (tokenAmount * roundDetails.releasePercentage) /
            100;
        uint256 lockAmount = (tokenAmount * lockPercentage) / 100;

        // transfer to buyer
        this.transfer(msg.sender, releaseAmount);

        // transfer to vesting
        this.transfer(address(vestingContract), lockAmount);
        vestingContract.setVestingSchedule(
            saleID,
            msg.sender,
            lockAmount,
            block.timestamp,
            roundDetails.lockPeriod,
            lockPercentage,
            30 days
        );

        if (!isBuyer[msg.sender]) {
            buyerDetails[msg.sender].buyerID = buyerId++;
            isBuyer[msg.sender] = true;
            buyers.push(msg.sender);
        }

        roundDetails.tokens -= tokenAmount; // Reduce the tokens left in the current round
        emit buyTokens(
            getCurrentRound(),
            msg.sender,
            tokenAmount,
            _saleAmount,
            roundDetails.price
        );
    }

    function getCurrentRound() public view returns (string memory) {
        if (block.timestamp <= rounds["Private Sale Round 1"].duration) {
            return "Private Sale Round 1";
        } else if (block.timestamp <= rounds["Private Sale Round 2"].duration) {
            return "Private Sale Round 2";
        } else if (block.timestamp <= rounds["Public Sale Round 1"].duration) {
            return "Public Sale Round 1";
        } else if (block.timestamp <= rounds["Public Sale Round 2"].duration) {
            return "Public Sale Round 2";
        } else if (block.timestamp <= rounds["Public Sale Round 3"].duration) {
            return "Public Sale Round 3";
        } else {
            return "All Sales Rounds Completed";
        }
    }

    function getCurrentAndPreviousRound()
        public
        view
        returns (string memory, string memory)
    {
        string memory currentRound;
        string memory previousRound;

        if (block.timestamp <= rounds["Private Sale Round 1"].duration) {
            currentRound = "Private Sale Round 1";
            previousRound = "";
        } else if (block.timestamp <= rounds["Private Sale Round 2"].duration) {
            currentRound = "Private Sale Round 2";
            previousRound = "Private Sale Round 1";
        } else if (block.timestamp <= rounds["Public Sale Round 1"].duration) {
            currentRound = "Public Sale Round 1";
            previousRound = "Private Sale Round 2";
        } else if (block.timestamp <= rounds["Public Sale Round 2"].duration) {
            currentRound = "Public Sale Round 2";
            previousRound = "Public Sale Round 1";
        } else if (block.timestamp <= rounds["Public Sale Round 3"].duration) {
            currentRound = "Public Sale Round 3";
            previousRound = "Public Sale Round 2";
        } else {
            currentRound = "All Sales Rounds Completed";
            previousRound = "Public Sale Round 3";
        }

        return (currentRound, previousRound);
    }

    function transferRemainingTokensToDeadWallet(string memory roundName)
        internal
    {
        uint256 remainingTokens = rounds[roundName].tokens;
        if (
            remainingTokens > 0 && block.timestamp > rounds[roundName].duration
        ) {
            _transfer(address(this), deadWallet, remainingTokens);
            rounds[roundName].tokens = 0;
        }
    }

    function getTokensLeftInCurrentRound() public view returns (uint256) {
        string memory currentRound = getCurrentRound();
        return rounds[currentRound].tokens;
    }

    function getCurrentRoundPrice() public view returns (uint256) {
        string memory currentRound = getCurrentRound();
        return rounds[currentRound].price;
    }

    function distributeAirdrop(string memory roundName, string memory fromRound)
        external
        onlyOwner
    {
        uint256 totalAirdropTokens = rounds[roundName].tokens;

        for (uint256 i = 0; i < buyers.length; i++) {
            address buyer = buyers[i];
            uint256 airdropAmount = (buyerDetails[buyer].roundPercentage[
                fromRound
            ] / 100) * totalAirdropTokens;
            _transfer(address(this), buyer, (airdropAmount / (1e2)));
            buyerDetails[buyer].airdropReceived += airdropAmount;
            rounds[roundName].tokens -= airdropAmount;
        }
    }

    function setSaleReceiver(address _newReceiver) external onlyOwner {
        require(_newReceiver != address(0), "Invalid Address");
        saleReceiver = _newReceiver;
    }

    function setUsdtTokenAddress(address _usdtToken) external onlyOwner {
        require(_usdtToken != address(0), "Invalid Address");
        usdtToken = IERC20(_usdtToken);
    }

    function updateRoundDetails(
        string memory roundName,
        SaleRound memory newDetails
    ) external onlyOwner {
        rounds[roundName] = newDetails;
    }

    function getBuyerData(address _buyer)
        public
        view
        returns (
            uint256 buyerID,
            uint256 buyerAmount,
            uint256 totalBuyPercentage,
            uint256 _airdropReceived,
            uint256 totalPaid,
            string[5] memory roundNames,
            uint256[5] memory roundPercentages
        )
    {
        buyerData storage data = buyerDetails[_buyer];
        string[5] memory _roundNames = [
            "Private Sale Round 1",
            "Private Sale Round 2",
            "Public Sale Round 1",
            "Public Sale Round 2",
            "Public Sale Round 3"
        ];
        uint256[5] memory _roundPercentages;

        for (uint256 i = 0; i < 5; i++) {
            if (bytes(_roundNames[i]).length > 0) {
                _roundPercentages[i] = data.roundPercentage[_roundNames[i]];
            }
        }

        return (
            data.buyerID,
            data.buyerAmount,
            data.totalBuyPercentage,
            data.airdropReceived,
            data.totalPaid,
            _roundNames,
            _roundPercentages
        );
    }

    function _getBuyerData(address _buyer)
        public
        view
        returns (
            uint256 buyerID,
            uint256 buyerAmount,
            uint256 totalBuyPercentage,
            uint256 _airdropReceived,
            uint256 totalPaid
        )
    {
        buyerData storage data = buyerDetails[_buyer];
        return (
            data.buyerID,
            data.buyerAmount,
            data.totalBuyPercentage,
            data.airdropReceived,
            data.totalPaid
        );
    }

    function removeTrashTokens(address _tokenAddress) external onlyOwner {
        require(_tokenAddress != address(this), "Cannot remove contract's own tokens");

        IERC20 token = IERC20(_tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        
        require(balance > 0, "No trash tokens to remove");

        // Transfer the tokens to the dead wallet
        token.transfer(deadWallet, balance);
    }

    function withdrawTokenFromContract(address _tokenAddress) external onlyOwner {

        IERC20 token = IERC20(_tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        
        require(balance > 0, "No trash tokens to remove");

        // Transfer the tokens to the owner wallet
        token.transfer(msg.sender, balance);
    }

}

                /*************************************************************\
                        Proudly Developed by Jaafar Krayem Copyright 2023
                \*************************************************************/
