// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/Math.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "./Pet.sol";

//根据等级 挖池子
contract Farm is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    Pet public pet;
    IERC20 public shibsc;
    uint256 constant public OneDay = 1 days;
    uint256 constant public Percent = 100;

    uint256 public starttime;
    uint256 public periodFinish = 0;
    //note that, you should combine the bonus rate to get the final production rate
    uint256 public rewardRate = 0;

    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;


    //staked power, 也就是所有参与的pet的等级
    uint256 private _totalSupply;
    //staked,对应的等级,0为没有参与,或者等级就是0,
    mapping(address => uint256) private _balances;


    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;//已记录但没有取走的
    mapping(address => uint256) public accumulatedRewards;
    address public minerOwner;

    address public feeManager;

    uint256 public fee = 0.004 ether;
    bool internal feeCharged = false;


    event RewardAdded(uint256 reward);
    event Join(address indexed user, uint256 amount);
    event Quit(address indexed user);
    event RewardPaid(address indexed user, uint256 reward);
    event TransferBack(address token, address to, uint256 amount);

    constructor(
        address _shibsc, //target
        address _pet, //source
        uint256 _starttime,
        address _minerOwner,
        address _feeManager
    ) public {
        require(_shibsc != address(0), "_token is zero address");
        require(_pet != address(0), "_lptoken is zero address");
        require(_minerOwner != address(0), "_minerOwner is zero address");

        pet = Pet(_pet);
        shibsc = IERC20(_shibsc);
        starttime = _starttime;
        minerOwner = _minerOwner;
        feeManager = _feeManager;
    }


    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }


    modifier checkStart() {
        require(block.timestamp >= starttime, 'Pool: not start');
        _;
    }

    modifier chargeFee(){
        bool lock = false;
        if (!feeCharged) {
            require(msg.value >= fee, "msg.value >= minimumFee");
            payable(feeManager).transfer(msg.value);
            feeCharged = true;
            lock = true;
        }
        _;
        if (lock) {
            feeCharged = false;
        }
    }


    //有人stake或者withdraw,totalSupply变了
    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        //全局变量
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {//initSet或者updateReward之外的
            rewards[account] = earned(account);
            //balance变了,导致balance*rewardPerToken的公式失效
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
            //从现在开始 之前的记为debt
        }
        _;
    }

    //累计计算RewardPerToken,用到了最新时间lastTimeRewardApplicable()
    //在updateReward的时候被调用,说明rate或者totalSupply变了
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply() == 0) {
            //保持不变
            return rewardPerTokenStored;
        }
        return
        rewardPerTokenStored.add(
            lastTimeRewardApplicable()//根据最后更新的时间戳 计算差值
            .sub(lastUpdateTime)
            .mul(rewardRate)
            .mul(1e18)
            .div(totalSupply())
        );
    }

    //008cc262
    //earned需要读取最新的rewardPerToken
    function earned(address account) public view returns (uint256) {
        return
        balanceOf(account)
        .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))//要减去debt
        .div(1e18)
        .add(rewards[account]);
        //每次更新debt的时候,也会更行rewards(因为balance变了,balance*rewardPerToken的计算会失效),所以要加回来
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function join()
    public
    payable
    updateReward(msg.sender)
    checkStart
    chargeFee
    {
        (,,,,,uint256 level) = pet.getProperty(msg.sender);
        require(level > 0, 'level > 0');

        uint256 old = _balances[msg.sender];
        _totalSupply = _totalSupply.sub(old);
        _totalSupply = _totalSupply.add(level);
        _balances[msg.sender] = level;

        emit Join(msg.sender, level);
    }

    function quit()
    public
    payable
    updateReward(msg.sender)
    checkStart
    chargeFee
    {
        uint256 old = _balances[msg.sender];
        _totalSupply = _totalSupply.sub(old);
        emit Quit(msg.sender);
    }

    //e9fad8ee
    function exit() external payable chargeFee {
        getReward();
        quit();
    }

    //3d18b912
    //hook the bonus when user getReward
    function getReward() public payable updateReward(msg.sender) checkStart chargeFee {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            rewards[msg.sender] = 0;
            shibsc.safeTransferFrom(minerOwner, msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
            accumulatedRewards[msg.sender] = accumulatedRewards[msg.sender].add(reward);
        }
    }

    function transferBack(IERC20 erc20Token, address to, uint256 amount) external onlyOwner {
        require(address(erc20Token) != address(pet), "For LPT, transferBack is not allowed, if you transfer LPT by mistake, sorry");

        if (address(erc20Token) == address(0)) {
            payable(to).transfer(amount);
        } else {
            erc20Token.safeTransfer(to, amount);
        }
        emit TransferBack(address(erc20Token), to, amount);
    }


    //you can call this function many time as long as block.number does not reach starttime and _starttime
    function initSet(uint256 _starttime, uint256 rewardPerDay, uint256 _periodFinish)
    external
    onlyOwner
    updateReward(address(0))
    {

        require(block.timestamp < starttime, "block.timestamp < starttime");

        require(block.timestamp < _starttime, "block.timestamp < _starttime");
        require(_starttime < _periodFinish, "_starttime < _periodFinish");

        starttime = _starttime;
        rewardRate = rewardPerDay.div(OneDay);
        periodFinish = _periodFinish;
        lastUpdateTime = starttime;
    }

    function updateRewardRate(uint256 rewardPerDay, uint256 _periodFinish)
    external
    onlyOwner
    updateReward(address(0))
    {
        if (_periodFinish == 0) {
            _periodFinish = block.timestamp;
        }

        require(starttime < block.timestamp, "starttime < block.timestamp");
        require(block.timestamp <= _periodFinish, "block.timestamp <= _periodFinish");

        rewardRate = rewardPerDay.div(OneDay);
        periodFinish = _periodFinish;
        lastUpdateTime = block.timestamp;
    }

    function changeMinerOwner(address _minerOwner) external onlyOwner {
        minerOwner = _minerOwner;
    }

    function changeFee(
        uint256 _fee,
        address _feeManager
    ) external onlyOwner {
        fee = _fee;
        feeManager = _feeManager;
    }

}
