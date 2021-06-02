// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract EthVault is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;
    constructor() public {}

    function take(IERC20 token, uint256 amount) payable onlyOwner external {
        if (address(token) == address(0)) {
            payable(owner()).sendValue(amount);


        } else {
            token.safeTransfer(owner(),amount);
        }
    }

    fallback() payable external{}
}
