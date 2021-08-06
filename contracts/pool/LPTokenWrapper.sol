// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public lpt;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function lpStake(uint256 amount) internal {
        uint256 amountBefore = lpt.balanceOf(address(this));
        lpt.safeTransferFrom(msg.sender, address(this), amount);
        uint256 amountAfter = lpt.balanceOf(address(this));
        amount = amountAfter.sub(amountBefore);

        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
    }

    function lpWithdraw(uint256 amount) internal {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        lpt.safeTransfer(msg.sender, amount);
    }

    function lpPayTax(uint256 amount, address to) internal {
        if (amount > 0) {
            _balances[msg.sender] = _balances[msg.sender].sub(amount);
            lpt.safeTransfer(to, amount);
        }
    }
}
