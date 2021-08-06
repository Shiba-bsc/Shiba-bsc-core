pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "./pool/UnlockPool.sol";

interface IFLOKI is IERC20 {

    function mintLockedToken(address to, uint256 amount) external;

    function reportStakeUnlockPool(address unlockStaker) external;

}
