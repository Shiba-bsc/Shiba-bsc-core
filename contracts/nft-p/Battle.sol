// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/Math.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "./Pet.sol";

//加入,然后可以当cooldown时间发起随机进攻,加入需要压入一定量的shibsc
//打胜的人 可以获得输掉的人的shibsc
//胜的人有5分钟的冷却才能重新加入
//败的人没有冷却就可立刻加入

contract Battle is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    Pet public pet;

    //if a pet of player is in arena
    mapping(address => bool) arena;
    //when the pet comes into arena
    mapping(address => uint256) preparing;
    //cooldown time
    mapping(address => uint256) cooldown;




    function transferBack(IERC20 erc20Token, address to, uint256 amount) external onlyOwner {
        require(address(erc20Token) != address(pet), "For LPT, transferBack is not allowed, if you transfer LPT by mistake, sorry");

        if (address(erc20Token) == address(0)) {
            payable(to).transfer(amount);
        } else {
            erc20Token.safeTransfer(to, amount);
        }
    }

}
