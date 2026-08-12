// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract presale is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    enum SaleState {
        Pending,
        Active,
        Ended,
        Finalized
    }

    IERC20 public immutable saleToken;
    IERC20 public immutable paymentToken;

    uint8 public immutable saleTokenDecimals;
    uint8 public immutable paymentTokenDecimals;

    uint256 public tokenPrice;
    uint256 public softCap;
    uint256 public hardCap;
    uint256 public minPurchase;
    uint256 public maxPurchase;

    uint256 public totalRaised;
    uint256 public totalTokensSold;
    uint256 public saleStart;
    uint256 public saleEnd;
    uint256 public totalClaimed;
    uint256 public constant PRICE_PRECISION = 1e6;

    bool public saleFinalized;
    bool public refundsEnabled;

    
    uint256 public vestingStart;       
    uint256 public vestingDuration;    
    uint256 public tgePercent;         
    uint256 public constant PERCENT_PRECISION = 100;
    uint256 public referralBonus = 5; // 5%
    uint256 public totalReferralRewards;
uint256 public totalReferralClaimed;
uint256 public constant MAX_BATCH_WHITELIST = 100;    //max created for batch whitelist

    mapping(address => uint256) public amountPaid;
    mapping(address => uint256) public tokensPurchased;
    mapping(address => uint256) public claimedAmount; 
    // Whitelist
mapping(address => bool) public whitelist;
bool public whitelistEnabled;

// Referral
mapping(address => address) public referrerOf;
mapping(address => uint256) public referralPurchased;
mapping(address => uint256) public referralClaimed;
mapping(address => uint256) public totalReferrals;



    //events

  


event TokensPurchased(address indexed buyer, uint256 paymentAmount, uint256 tokenAmount);
event TokenClaimed(address indexed buyer, uint256 amount);
event RefundClaimed(address indexed buyer, uint256 amount);
event SaleFinalized(bool successful);
event RescueToken(address token, uint256 amount);
event VestingConfigured(uint256 vestingStart, uint256 vestingDuration, uint256 tgePercent);

// Admin Events
event TokenPriceUpdated(uint256 oldPrice, uint256 newPrice);

event PurchaseLimitsUpdated(
    uint256 oldMinPurchase,
    uint256 newMinPurchase,
    uint256 oldMaxPurchase,
    uint256 newMaxPurchase
);

event SaleTimeUpdated(
    uint256 oldSaleStart,
    uint256 newSaleStart,
    uint256 oldSaleEnd,
    uint256 newSaleEnd
);

event SaleTokensDeposited(address indexed owner, uint256 amount);

event SaleExtended(uint256 oldSaleEnd, uint256 newSaleEnd);

event SaleCancelled();

event FundsWithdrawn(address indexed owner, uint256 amount);

event UnsoldTokensWithdrawn(address indexed owner, uint256 amount);

event RescueETH(address indexed owner, uint256 amount);

event WhitelistStatusUpdated(bool enabled);

event Whitelisted(address indexed user);

event RemovedFromWhitelist(address indexed user);

event ReferralRecorded(
    address indexed buyer,
    address indexed referrer
);

event ReferralRewardEarned(
    address indexed referrer,
    uint256 reward
);

event ReferralRewardClaimed(
    address indexed referrer,
    uint256 amount
);

    constructor(
        address _saleToken,
        address _paymentToken,
        uint256 _tokenPrice,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _minPurchase,
        uint256 _maxPurchase,
        uint256 _saleStart,
        uint256 _saleEnd,
        uint256 _vestingDuration,
        uint256 _tgePercent
    ) Ownable(msg.sender) {

        require(_saleToken != address(0), "Invalid sale token");
        require(_paymentToken != address(0), "Invalid payment token");
        require(_saleToken != _paymentToken, "Tokens must differ");
        require(_tokenPrice > 0, "Invalid price");
        require(_softCap > 0, "Invalid soft Cap");
        require(_hardCap > _softCap, "Hard cap > Soft cap");

        require(_minPurchase > 0, "Invalid min purchase");
        require(_maxPurchase >= _minPurchase, "Invalid max purchase");
        require(_vestingDuration > 0, "Invalid vesting");

        require(_saleStart < _saleEnd, "Invalid Time");
        require(_saleStart >= block.timestamp, "Sale already started");
        require(_tgePercent <= PERCENT_PRECISION, "Invalid TGE percent");

        saleToken = IERC20(_saleToken);
        paymentToken = IERC20(_paymentToken);
        tokenPrice = _tokenPrice;
        saleTokenDecimals = IERC20Metadata(_saleToken).decimals();
        paymentTokenDecimals = IERC20Metadata(_paymentToken).decimals();
        softCap = _softCap;
        hardCap = _hardCap;
        minPurchase = _minPurchase;
        maxPurchase = _maxPurchase;
        saleStart = _saleStart;
        saleEnd = _saleEnd;
        vestingDuration = _vestingDuration;
        tgePercent = _tgePercent;
    }


    //functions

    function getSaleState() public view returns (SaleState) {
        if (saleFinalized) { return SaleState.Finalized; }
        if (block.timestamp < saleStart) { return SaleState.Pending; }
        if (block.timestamp <= saleEnd) { return SaleState.Active; }
        return SaleState.Ended;
    }
//to buy tokens
   function buyTokens(uint256 paymentAmount, address referrer) external nonReentrant whenNotPaused {
    _buyTokens(msg.sender, paymentAmount, referrer);
}

  

 //to claim token
    function claimableAmount(address user) public view returns (uint256) {
        if (!saleFinalized || refundsEnabled || vestingStart == 0) return 0;

        uint256 totalPurchased = tokensPurchased[user];
        if (totalPurchased == 0) return 0;

        uint256 tgeAmount = (totalPurchased * tgePercent) / PERCENT_PRECISION;
        uint256 remaining = totalPurchased - tgeAmount;

        uint256 vestedAmount;
        if (block.timestamp < vestingStart) {
            vestedAmount = tgeAmount;
        } else if (vestingDuration == 0 || block.timestamp >= vestingStart + vestingDuration) {
            vestedAmount = totalPurchased; // fully vested
        } else {
            uint256 elapsed = block.timestamp - vestingStart;
            vestedAmount = tgeAmount + (remaining * elapsed) / vestingDuration;
        }

        uint256 alreadyClaimed = claimedAmount[user];
        if (vestedAmount <= alreadyClaimed) return 0;
        return vestedAmount - alreadyClaimed;
    }

    //claim tokens
    function claimTokens() external nonReentrant whenNotPaused {
        require(saleFinalized, "sale not finalized");
        require(!refundsEnabled, "refunds enabled");

        uint256 claimable = claimableAmount(msg.sender);
        require(claimable > 0, "nothing to claim");

        claimedAmount[msg.sender] += claimable;
        totalClaimed += claimable;

        saleToken.safeTransfer(msg.sender, claimable);
        emit TokenClaimed(msg.sender, claimable);
    }

    //claim refund

   function claimRefund() external nonReentrant whenNotPaused {
        require(saleFinalized, "sale not finalized");
        require(refundsEnabled, "refunds Unavailable");
        uint256 amount = amountPaid[msg.sender];
        require(amount > 0, "Nothing to Refund");
        uint256 refundedTokens = tokensPurchased[msg.sender];


address referrer = referrerOf[msg.sender];

if (referrer != address(0)) {
    uint256 reward =
        (refundedTokens * referralBonus) /
        PERCENT_PRECISION;

    referralPurchased[referrer] -= reward;
    totalReferralRewards -= reward;
}

amountPaid[msg.sender] = 0;
tokensPurchased[msg.sender] = 0;

totalTokensSold -= refundedTokens;
totalRaised -= amount;


        paymentToken.safeTransfer(msg.sender, amount);
        emit RefundClaimed(msg.sender, amount);
    }



    //only ownwer functions


     //finalize sale
    function finalizeSale() external onlyOwner {
        require(getSaleState() == SaleState.Ended, "sale not ended");
        saleFinalized = true;
        if (totalRaised < softCap) {
            refundsEnabled = true;
        } else {
            vestingStart = block.timestamp;
            emit VestingConfigured(vestingStart, vestingDuration, tgePercent);
        }
        emit SaleFinalized(!refundsEnabled);
    }

    //withdaw funds

    function withdrawFunds() external onlyOwner nonReentrant{
        require(saleFinalized, "sale not finalized yet");
        require(!refundsEnabled, "refund  not enabled");
        uint256 balance = paymentToken.balanceOf(address(this));
        paymentToken.safeTransfer(owner(), balance);
        emit FundsWithdrawn(owner(), balance);
    }
//to withdraw unsold tokens
    function withdrawUnsoldTokens() external onlyOwner {

        require(saleFinalized, "Sale not finalized");
        require(!refundsEnabled, "Refund mode");
        uint256 balance = saleToken.balanceOf(address(this));
        uint256 reserved =
    (totalTokensSold - totalClaimed) +
    (totalReferralRewards - totalReferralClaimed);
        uint256 unsold = balance - reserved;
        require(unsold > 0, "No unsold tokens");
        saleToken.safeTransfer(owner(), unsold);
        emit UnsoldTokensWithdrawn(owner(), unsold);
    }


    //update token price
   

function updateTokenPrice(uint256 newPrice) external onlyOwner {
    require(getSaleState() == SaleState.Pending, "Sale already started");
    require(newPrice > 0, "Invalid price");

    uint256 oldPrice = tokenPrice;
    tokenPrice = newPrice;

    emit TokenPriceUpdated(oldPrice, newPrice);
}
//update purchase limits
function updatePurchaseLimits(uint256 newMin, uint256 newMax)
external onlyOwner{
    require(getSaleState() == SaleState.Pending, "Sale already started");
    require(newMin >0,"Invalid Minimum");
    require(newMax>=newMin,"Inavlid Maximum");
    uint256 oldMin = minPurchase;
    uint256 oldMax = maxPurchase;
    minPurchase = newMin;
    maxPurchase = newMax;
    emit PurchaseLimitsUpdated(oldMin, newMin, oldMax, newMax);


}

//update sale time
function updateSaleTime(uint256 newStart, uint256 newEnd) external onlyOwner {
    require(getSaleState() == SaleState.Pending, "Sale already started");
    require(newStart < newEnd, "Invalid time");
    require(newStart >= block.timestamp, "Start in past");
    uint256 oldStart = saleStart;
    uint oldEnd = saleEnd;


    saleStart = newStart;
    saleEnd = newEnd;
    emit SaleTimeUpdated(oldStart, newStart, oldEnd, newEnd);

}

//deposit sale tokens
function depositSaleTokens( uint256 amount)external onlyOwner{
    require(amount>0,"Invalid amount");
    saleToken.safeTransferFrom(msg.sender,address(this), amount);
    emit SaleTokensDeposited(msg.sender, amount);

}

//to see data
//see remaining tokens
function remainingTokens() external view returns (uint256) {
    uint256 reserved =
        (totalTokensSold - totalClaimed) +
        (totalReferralRewards - totalReferralClaimed);

    return saleToken.balanceOf(address(this)) - reserved;
}



//see remaining hardcap

function remainingHardCap()external view returns(uint256 amount){
    return hardCap- totalRaised;
}


//getUserInfo
function getUserInfo(address user)
    external
    view
    returns (
        uint256 paid,
        uint256 purchased,
        uint256 claimed,
        uint256 claimable
    )
{
    return (
        amountPaid[user],
        tokensPurchased[user],
        claimedAmount[user],
        claimableAmount(user)
    );
}

//get sale Info
function getSaleInfo()
    external
    view
    returns (
        SaleState state,
        uint256 raised,
        uint256 sold,
        uint256 soft,
        uint256 hard,
        uint256 remainingCap
    )
{
    return (
        getSaleState(),
        totalRaised,
        totalTokensSold,
        softCap,
        hardCap,
        hardCap - totalRaised
    );
} 

//extend sale
function extendSale(uint256 newSaleEnd) external onlyOwner {
    require(getSaleState() == SaleState.Active, "Sale not active");
    require(newSaleEnd > saleEnd, "Invalid end time");

    uint256 oldEnd = saleEnd;
    saleEnd = newSaleEnd;

    emit SaleExtended(oldEnd, newSaleEnd);
}

//cancel sale

function cancelSale()external onlyOwner{
    require(!saleFinalized,"Already Finalized");
    saleFinalized = true;
    refundsEnabled = true;
    emit SaleCancelled();
}

//set whitelist enabled
function setWhitelistEnabled(bool enabled) external onlyOwner {
    whitelistEnabled = enabled;

    emit WhitelistStatusUpdated(enabled);
}


//add address to whitelist
function addToWhitelist(address user)external onlyOwner{
    whitelist[user]=true;

    emit Whitelisted(user);
}


//remove address to whitelist
function removeFromWhitelist(address user)external onlyOwner{
    whitelist[user]=false;

    emit RemovedFromWhitelist(user);
}


//add in bulk


function batchWhitelist(address[] calldata users)
    external
    onlyOwner
{
    require(users.length > 0, "Empty array");
    require(
        users.length <= MAX_BATCH_WHITELIST,
        "Batch limit exceeded"
    );

    for (uint256 i = 0; i < users.length; i++) {
        whitelist[users[i]] = true;
        emit Whitelisted(users[i]);
    }
}



function referralClaimable(address user)
    public
    view
    returns(uint256)
{
    if (!saleFinalized || refundsEnabled || vestingStart == 0)
        return 0;

    uint256 totalReward = referralPurchased[user];

    if(totalReward == 0)
        return 0;

    uint256 tgeAmount =
        totalReward *
        tgePercent /
        PERCENT_PRECISION;

    uint256 remaining =
        totalReward -
        tgeAmount;

    uint256 vested;

    if(block.timestamp < vestingStart){

        vested = tgeAmount;

    } else if(
        vestingDuration == 0 ||
        block.timestamp >= vestingStart + vestingDuration
    ){

        vested = totalReward;

    } else{

        uint256 elapsed =
            block.timestamp -
            vestingStart;

        vested =
            tgeAmount +
            (remaining * elapsed) /
            vestingDuration;
    }

    if(vested <= referralClaimed[user])
        return 0;

    return vested - referralClaimed[user];
}



//to claim referral rewards
function claimReferralRewards()
    external
    nonReentrant
    whenNotPaused
{
    require(saleFinalized, "Sale not finalized");
    require(!refundsEnabled, "Refund mode");

    uint256 reward =
        referralClaimable(msg.sender);

    require(
        reward > 0,
        "Nothing to claim"
    );

    referralClaimed[msg.sender] += reward;
    totalReferralClaimed += reward;

    saleToken.safeTransfer(
        msg.sender,
        reward
    );

    emit ReferralRewardClaimed(
        msg.sender,
        reward
    );
}




function _buyTokens(
    address buyer,
    uint256 paymentAmount,
    address referrer
) internal {

    require(getSaleState() == SaleState.Active, "Sale not active");

    if (whitelistEnabled) {
        require(
            whitelist[buyer] && whitelist[msg.sender],
            "Not whitelisted"
        );
    }

    require(
        paymentAmount >= minPurchase,
        "Below minimum purchase"
    );

    require(
        amountPaid[buyer] + paymentAmount <= maxPurchase,
        "Max purchase exceeded"
    );

    uint256 tokenAmount =
        (paymentAmount * (10 ** saleTokenDecimals) * PRICE_PRECISION) /
        (tokenPrice * (10 ** paymentTokenDecimals));

    require(tokenAmount > 0, "Payment too small for price");

    // Existing referrer (if any)
    address recordedReferrer = referrerOf[buyer];

uint256 reward = 0;

if (
    recordedReferrer != address(0) ||
    (
        buyer == msg.sender &&
        referrer != address(0) &&
        referrer != buyer &&
        recordedReferrer == address(0)
    )
) {
    reward =
        (tokenAmount * referralBonus) /
        PERCENT_PRECISION;
}

    require(
    saleToken.balanceOf(address(this)) >=
        totalTokensSold +
        totalReferralRewards +
        tokenAmount +
        reward,
    "Insufficient sale token supply"
);

    require(
        totalRaised + paymentAmount <= hardCap,
        "Hard cap reached"
    );

    // Record referrer only once
    if (
        buyer == msg.sender &&
        referrer != address(0) &&
        referrer != buyer &&
        referrerOf[buyer] == address(0)
    ) {
        referrerOf[buyer] = referrer;
        totalReferrals[referrer]++;

        recordedReferrer = referrer;

       

        emit ReferralRecorded(
            buyer,
            referrer
        );
    }

    amountPaid[buyer] += paymentAmount;
    tokensPurchased[buyer] += tokenAmount;

    totalRaised += paymentAmount;
    totalTokensSold += tokenAmount;

    paymentToken.safeTransferFrom(
        msg.sender,
        address(this),
        paymentAmount
    );

    if (recordedReferrer != address(0)) {
        referralPurchased[recordedReferrer] += reward;
        totalReferralRewards += reward;

        emit ReferralRewardEarned(
            recordedReferrer,
            reward
        );
    }

    emit TokensPurchased(
        buyer,
        paymentAmount,
        tokenAmount
    );
}

//for gifting
function buyTokensFor(
    address beneficiary,
    uint256 paymentAmount
    
)
external
nonReentrant
whenNotPaused
{
    _buyTokens(
        beneficiary,
        paymentAmount,
        address(0)  
    );
}









 function rescueToken(address token, uint256 amount) external onlyOwner {
    require(token != address(saleToken), "Cannot rescue sale token");
    IERC20(token).safeTransfer(owner(), amount);
    emit RescueToken(token, amount);
}
function rescueETH(uint256 amount) external onlyOwner nonReentrant{
    require(address(this).balance >= amount, "Insufficient ETH");

    (bool success, ) = payable(owner()).call{value: amount}("");
    require(success, "ETH transfer failed");
    emit RescueETH(owner(), amount);
}

function pause() external onlyOwner {
    _pause();
}

function unpause() external onlyOwner {
    _unpause();
}

    receive() external payable {}
}