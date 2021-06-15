// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract MultiTransferCharge is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public fee;

    constructor(uint256 _fee) public {
        fee = _fee;
    }

    modifier chargeEth(){
        uint256 inputValue = msg.value;
        uint256 beforeXfer = address(this).balance;
        _;
        uint256 afterXfer  = address(this).balance;
        uint256 inputFee = inputValue.sub(beforeXfer.sub(afterXfer));
        require(inputFee >= fee,"inputFee >= fee");
    }

    function dispatch(IERC20 token, address payable[] calldata to, uint256[] calldata amount) payable chargeEth external {
        require(to.length == amount.length, "to.length == amount.length");
        if (address(token) == address(0)) {
            for (uint256 i = 0; i < to.length; i++) {
                to[i].sendValue(amount[i]);
            }
        } else {
            for (uint256 i = 0; i < to.length; i++) {
                token.safeTransferFrom(msg.sender, to[i], amount[i]);
            }
        }
    }

    function transferBack(IERC20 erc20Token, address to, uint256 amount) external onlyOwner {
        if (address(erc20Token) == address(0)) {
            //ignore potential exceptions
            payable(to).transfer(amount);
        } else {
            erc20Token.safeTransfer(to, amount);
        }
    }

    function changeFee(uint256 _fee) external onlyOwner{
        fee = _fee;
    }
}
