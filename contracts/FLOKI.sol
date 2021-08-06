pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./pool/UnlockPool.sol";

contract FLOKI is IFLOKI, ERC20Capped, Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 constant public OneDay = 1 days;

    uint256 public constant MULTIPLIER = 10 ** 8;

    uint256 public constant CAP = 10 ** 9 * 10 ** 18;

    uint256 public totalUnlocked;

    mapping(address => uint256) private unlocks;

    //unlockStaker => unlockPool => last unlock block.timestap
    mapping(address => mapping(address => uint256)) public lastUnlockTimestamp;


    //unlockPool => max unlock token per second
    mapping(address => uint256) public maximalUnlockSpeed;

    mapping(address => bool) public unlockPools;

    mapping(address => bool) public mintPools;


    constructor () public ERC20Capped(CAP) ERC20("FLOKI-TEST", "FLOKITEST"){
        mintUnlockedToken(owner(), 10 ** 6 * 10 ** 18);
    }

    modifier onlyMintPoolOrOwner() {
        require(msg.sender == owner() || mintPools[msg.sender], "onlyMintPoolOrOwner");
        _;
    }

    modifier onlyUnlockPool {
        require(unlockPools[msg.sender], "onlyUnlockPool");
        _;
    }


    function unlockedOf(address account) external view returns (uint256) {
        return unlocks[account];
    }

    function lockedOf(address account) public view returns (uint256) {
        return balanceOf(account).sub(unlocks[account]);
    }

    function getUnlockSpeed(address unlockPoolStaker, address unlockPool) external view returns (uint256) {
        require(unlockPools[unlockPool], "_unlockPool doesn't exist");

        return calcUnlockSpeed(unlockPoolStaker, unlockPool);
    }

    //return all claimable unlocked token for certain user in case of certain unlockPool
    function claimableUnlocked(address unlockStaker, address unlockPool) external view returns (uint256) {
        return calcUnlockAmount(unlockStaker, unlockPool);
    }

    //unlock transfer成功才可以
    function transfer(address recipient, uint256 amount) public override(IERC20, ERC20) returns (bool) {
        _transfer(msg.sender, recipient, amount);
        unlockTransfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override(IERC20, ERC20) returns (bool) {
        _transfer(sender, recipient, amount);
        unlockTransfer(sender, recipient, amount);
        uint256 allowance = allowance(sender, msg.sender);
        _approve(sender, msg.sender, allowance.sub(amount, "TRANSFER_AMOUNT_EXCEEDED"));
        return true;
    }

    function claimUnlocked(address unlockPool) external nonReentrant returns (bool) {
        uint256 unlockedAmount = calcUnlockAmount(msg.sender, unlockPool);
        lastUnlockTimestamp[msg.sender][unlockPool] = block.timestamp;
        unlock(msg.sender, unlockedAmount);
        return true;
    }


    function mintUnlockedToken(address to, uint256 amount) onlyMintPoolOrOwner public {
        _mint(to, amount);
        unlock(to, amount);
    }

    function mintLockedToken(address to, uint256 amount) onlyMintPoolOrOwner override external {
        _mint(to, amount);
    }

    function reportStakeUnlockPool(address unlockStaker) onlyUnlockPool override external {
        if (lastUnlockTimestamp[unlockStaker][msg.sender] == 0) {
            lastUnlockTimestamp[unlockStaker][msg.sender] = block.timestamp;
        }
    }

    //如果没有质押,或者已经在当前块被unlock了,那么返回0
    function calcUnlockAmount(address unlockStaker, address unlockPool) internal view returns (uint256) {

        if (lastUnlockTimestamp[unlockStaker][unlockPool] == 0) {
            return 0;
        }

        uint256 unlockAmount = UnlockPool(unlockPool).earned(unlockStaker);

        uint256 delta = block.timestamp.sub(lastUnlockTimestamp[unlockStaker][unlockPool]);
        uint256 maxUnlockAmount = maximalUnlockSpeed[unlockPool].mul(delta);

        if (unlockAmount > maxUnlockAmount) {
            unlockAmount = maxUnlockAmount;
        }

        //不应该超过locked
        uint256 lockedAmount = lockedOf(unlockStaker);
        if (unlockAmount > lockedAmount) {
            unlockAmount = lockedAmount;
        }

        return unlockAmount;
    }


    //计算解锁速度,单位是每一秒
    //在unlockPool 首次stake的时候 需要通知FLOKI,否则有返回reward,但是不知道首次质押是什么时间
    //如果没有unlock时间,也就意味着没有首次质押时间,那么返回0
    //如果没有时间差,说明在当前块已经被unlock过了,那么返回0
    function calcUnlockSpeed(address unlockStaker, address unlockPool) internal view returns (uint256) {
        if (lastUnlockTimestamp[unlockStaker][unlockPool] == 0) {
            return 0;
        }

        uint256 delta = block.timestamp.sub(lastUnlockTimestamp[unlockStaker][unlockPool]);
        if (delta == 0) {
            return 0;
        }
        uint256 reward = UnlockPool(unlockPool).earned(unlockStaker);


        uint256 originalSpeed = reward.div(delta);

        if (originalSpeed > maximalUnlockSpeed[unlockPool]) {
            originalSpeed = maximalUnlockSpeed[unlockPool];
        }

        return originalSpeed;
    }


    function unlock(address recipient, uint256 amount) internal {

        unlocks[recipient] = unlocks[recipient].add(amount);
        require(unlocks[recipient] <= balanceOf(recipient), "unlocks should never exceed balance");
        totalUnlocked = totalUnlocked.add(amount);
    }


    function unlockTransfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        unlocks[sender] = unlocks[sender].sub(amount, "ERC20: transfer amount exceeds unlocked balance");
        unlocks[recipient] = unlocks[recipient].add(amount);
    }

    function changeMintPool(address mintPool, bool registry) onlyOwner external {
        mintPools[mintPool] = registry;
    }

    function changeUnlockPool(address unlockPool, bool registry) onlyOwner external {
        unlockPools[unlockPool] = registry;
    }

    function changeMaximalUnlockSpeed(address unlockPool, uint256 speedPerDay) onlyOwner external {
        maximalUnlockSpeed[unlockPool] = speedPerDay.div(OneDay);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override(ERC20Capped) {
        ERC20Capped._beforeTokenTransfer(from, to, amount);
    }
}
