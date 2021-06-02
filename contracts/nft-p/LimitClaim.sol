pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BasicNFT.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


//spend shard to get basic nft
contract LimitClaim is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public shard;

    struct Commodity {
        BasicNFT part;
        uint256 kind;
        uint256 shardPrize;
        uint256 left;
    }

    //BasicNFT => kind => Commodity
    mapping(BasicNFT => mapping(uint256 => Commodity)) inventory;

    constructor(IERC20 _shard) public {
        shard = _shard;
    }

    function claim(BasicNFT part, uint256 kind) external {
        Commodity storage good = inventory[part][kind];
        require(address(good.part) != address(0), "empty inventory");

        uint256 balance = shard.balanceOf(msg.sender);
        require(balance >= good.shardPrize, "balance >= good.shardPrize");

        good.left = good.left.sub(1);
        good.part.newItem(msg.sender, kind);


    }
}
