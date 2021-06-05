// SPDX-License-Identifier: MIT

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import "@openzeppelin/contracts/math/SafeMath.sol";
import '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import "@openzeppelin/contracts/access/Ownable.sol";

// this erc20 is modified for etherscan
import './ERC20.sol';

pragma solidity ^0.6.0;

contract DeployERC20 is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public shibsc;

    uint256 public shibscFee;
    uint256 public bnbFee;
    address feeManager;

    mapping(address => address[]) public records;

    event NewERC20(address indexed deployer, address indexed erc20);

    constructor(IERC20 _shibsc, uint256 _shibscFee, uint256 _bnbFee, address _feeManager) public {
        shibsc = _shibsc;
        shibscFee = _shibscFee;
        bnbFee = _bnbFee;
        feeManager = _feeManager;
    }

    function deployInstance(string memory name_, string memory symbol_, address init_holder_, uint256 total_) external payable {
        chargeFee();

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

    function chargeFee() internal {
        if (msg.value == 0) {
            shibsc.safeTransferFrom(msg.sender, feeManager, shibscFee);
        }
        else {
            require(msg.value >= bnbFee, "msg.value >= bnbFee");
            payable(feeManager).transfer(msg.value);
        }
    }

    function changeFee(uint256 _shibscFee, uint256 _bnbFee) external onlyOwner {
        shibscFee = _shibscFee;
        bnbFee = _bnbFee;
    }
}

