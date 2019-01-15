pragma solidity ^0.4.25;

contract IStdToken {
    function balanceOf(address _owner) public view returns (uint256);
    function transfer(address _to, uint256 _value) public returns (bool);
    function transferFrom(address _from, address _to, uint256 _value) public returns(bool);
}

contract PoolCommon {
    
    //main adrministrators of the Etherama network
    mapping(address => bool) private _administrators;

    //main managers of the Etherama network
    mapping(address => bool) private _managers;

    
    modifier onlyAdministrator() {
        require(_administrators[msg.sender]);
        _;
    }

    modifier onlyAdministratorOrManager() {
        require(_administrators[msg.sender] || _managers[msg.sender]);
        _;
    }
    
    constructor() public {
        _administrators[msg.sender] = true;
    }
    
    
    function addAdministator(address addr) onlyAdministrator public {
        _administrators[addr] = true;
    }

    function removeAdministator(address addr) onlyAdministrator public {
        _administrators[addr] = false;
    }

    function isAdministrator(address addr) public view returns (bool) {
        return _administrators[addr];
    }

    function addManager(address addr) onlyAdministrator public {
        _managers[addr] = true;
    }

    function removeManager(address addr) onlyAdministrator public {
        _managers[addr] = false;
    }
    
    function isManager(address addr) public view returns (bool) {
        return _managers[addr];
    }
}

contract PoolCore is PoolCommon {
    uint256 constant public MAGNITUDE = 2**64;

    //MNTP token reward per share
    uint256 public mntpRewardPerShare;
    //GOLD token reward per share
    uint256 public goldRewardPerShare;

    //Total MNTP tokens held by users
    uint256 public totalMntpHeld;

    //mntp reward per share
    mapping(address => uint256) private _mntpRewardPerShare;   

    //gold reward per share
    mapping(address => uint256) private _goldRewardPerShare;  

    address public controllerAddress;

    mapping(address => uint256) private _rewardMntpPayouts;
    mapping(address => uint256) private _rewardGoldPayouts;

    mapping(address => uint256) private _userStakes;

    IStdToken public mntpToken;
    IStdToken public goldToken;


    modifier onlyController() {
        require(controllerAddress == msg.sender);
        _;
    }

    constructor(address mntpTokenAddr, address goldTokenAddr) PoolCommon() public {
        mntpToken = IStdToken(mntpTokenAddr);
        goldToken = IStdToken(goldTokenAddr);
    }
    
    function addHeldTokens(address userAddress, uint256 tokenAmount) onlyController public {
        _userStakes[userAddress] = SafeMath.add(_userStakes[userAddress], tokenAmount);
        totalMntpHeld = SafeMath.add(totalMntpHeld, tokenAmount);
        
        addUserPayouts(userAddress, mntpRewardPerShare * tokenAmount, goldRewardPerShare * tokenAmount);
    }

    function addRewardPerShare(uint256 mntpReward, uint256 goldReward) onlyController public {
        require(totalMntpHeld > 0);

        uint256 mntpShareReward = (mntpReward * MAGNITUDE) / totalMntpHeld;
        uint256 goldShareReward = (goldReward * MAGNITUDE) / totalMntpHeld;

        mntpRewardPerShare = SafeMath.add(mntpRewardPerShare, mntpShareReward);
        goldRewardPerShare = SafeMath.add(mntpRewardPerShare, goldShareReward);
    }  
    
    function addUserPayouts(address userAddress, uint256 mntpReward, uint256 goldReward) onlyController public {
        _rewardMntpPayouts[userAddress] = SafeMath.add(_rewardMntpPayouts[userAddress], mntpReward);
        _rewardGoldPayouts[userAddress] = SafeMath.add(_rewardGoldPayouts[userAddress], goldReward);
    }

    function getMntpTokenUserReward(address userAddress) public view returns(uint256 reward) {  
        reward = mntpRewardPerShare * getUserStake(userAddress);
        reward = ((reward < getUserMntpRewardPayouts(userAddress)) ? 0 : SafeMath.sub(reward, getUserMntpRewardPayouts(userAddress))) / MAGNITUDE;

        return reward;
    }
    
    function getGoldTokenUserReward(address userAddress) public view returns(uint256 reward) {  
        reward = goldRewardPerShare * getUserStake(userAddress);
        reward = ((reward < getUserGoldRewardPayouts(userAddress)) ? 0 : SafeMath.sub(reward, getUserGoldRewardPayouts(userAddress))) / MAGNITUDE;

        return reward;
    }
    
    function getUserMntpRewardPayouts(address userAddress) public view returns(uint256) {
        return _rewardMntpPayouts[userAddress];
    }    
    
    function getUserGoldRewardPayouts(address userAddress) public view returns(uint256) {
        return _rewardGoldPayouts[userAddress];
    }    
    
    function getUserStake(address userAddress) public view returns(uint256) {
        return _userStakes[userAddress];
    }    

}


contract GoldmintPool {

    address public tokenBankAddress = address(0x0);

    PoolCore public core;
    IStdToken public mntpToken;
    IStdToken public goldToken;
    
    event onDistribShareProfit(uint256 mntpReward, uint256 goldReward); 
    event onUserRewardWithdrawn(address indexed userAddress, uint256 mntpReward, uint256 goldReward);
    event onHoldStake(address indexed userAddress, uint256 mntpAmount);
    event onUnholdStake(address indexed userAddress, uint256 mntpAmount);

    modifier onlyAdministrator() {
        require(core.isAdministrator(msg.sender));
        _;
    }

    modifier onlyAdministratorOrManager() {
        require(core.isAdministrator(msg.sender) || core.isManager(msg.sender));
        _;
    }
    
    modifier notNullAddress(address addr) {
        require(addr != address(0x0));
        _;
    }

    constructor(address coreAddr, address tokenBankAddr) notNullAddress(coreAddr) notNullAddress(tokenBankAddr) public { 
        core = PoolCore(coreAddr);
        mntpToken = core.mntpToken();
        goldToken = core.goldToken();
        
        tokenBankAddress = tokenBankAddr;
    }
    
    function setTokenBankAddress(address addr) onlyAdministrator notNullAddress(addr) public {
        tokenBankAddress = addr;
    }
    
    function holdStake(uint256 mntpAmount) public {
        require(mntpToken.balanceOf(msg.sender) > 0);
        
        mntpToken.transferFrom(msg.sender, address(this), mntpAmount);
        core.addHeldTokens(msg.sender, mntpAmount);
        
        emit onHoldStake(msg.sender, mntpAmount);
    }
    
    function unholdStake() public {
        uint256 amount = core.getUserStake(msg.sender);
        
        require(amount > 0);
        require(getMntpBalance() >= amount);

        mntpToken.transfer(msg.sender, amount);
        
        emit onUnholdStake(msg.sender, amount);
    }
    
    function distribShareProfit(uint256 mntpReward, uint256 goldReward) onlyAdministratorOrManager public {
        if (mntpReward > 0) mntpToken.transferFrom(tokenBankAddress, address(this), mntpReward);
        if (goldReward > 0) goldToken.transferFrom(tokenBankAddress, address(this), goldReward);
        
        core.addRewardPerShare(mntpReward, goldReward);
        
        emit onDistribShareProfit(mntpReward, goldReward);
    }

    function withdrawUserReward() public {
        
        uint256 mntpReward = core.getMntpTokenUserReward(msg.sender);
        uint256 goldReward = core.getGoldTokenUserReward(msg.sender);
        
        require(mntpReward > 0 || goldReward > 0);
        
        require(getMntpBalance() >= mntpReward);
        require(getGoldBalance() >= goldReward);
        
        core.addUserPayouts(msg.sender, mntpReward, goldReward);
        
        if (mntpReward > 0) mntpToken.transfer(msg.sender, mntpReward);
        if (goldReward > 0) goldToken.transfer(msg.sender, goldReward);
        
        emit onUserRewardWithdrawn(msg.sender, mntpReward, goldReward);
    }
    

    // HELPERS

    function getMntpBalance() view public returns(uint256) {
        return mntpToken.balanceOf(address(this));
    }

    function getGoldBalance() view public returns(uint256) {
        return goldToken.balanceOf(address(this));
    }

}


library SafeMath {

    /**
    * @dev Multiplies two numbers, throws on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    /**
    * @dev Substracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    } 

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }   

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? b : a;
    }   
}