// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract EthDispatcher is Ownable{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;
    constructor()public{}

    function dispatch(IERC20 token, address payable[] calldata to, uint256[] calldata amount) payable onlyOwner external{
        require(to.length == amount.length,"to.length == amount.length");
        if(address(token) == address (0)){
            for(uint256 i = 0; i< to.length; i++){
                to[i].sendValue(amount[i]);
            }

        }else{
            for(uint256 i = 0; i< to.length; i++){
                token.safeTransferFrom(msg.sender,to[i],amount[i]);
            }
        }
    }
}
