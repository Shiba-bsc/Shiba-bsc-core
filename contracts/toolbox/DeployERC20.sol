// SPDX-License-Identifier: MIT

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
// this erc20 is modified for etherscan
import './ERC20.sol';

pragma solidity ^0.6.0;

contract DeployERC20 {

    mapping(address => address[]) public records;


    event NewERC20(address indexed deployer, address indexed erc20);


    constructor() public {

    }

    function deployInstance(string memory name_, string memory symbol_, address init_holder_, uint256 total_) external {
        // this erc20 is modified for etherscan
        ERC20 erc20 = new ERC20();

        require(address(erc20) != address(0), "deploy erc20 fails");

        erc20.init(name_, symbol_, init_holder_, total_);

        records[msg.sender].push(address(erc20));
        emit NewERC20(msg.sender, address(erc20));
    }

    function recordLength(address deployer) external view returns (uint256){
        return records[deployer].length;
    }
}

