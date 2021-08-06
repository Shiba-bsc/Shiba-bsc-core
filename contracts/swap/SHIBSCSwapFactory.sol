pragma solidity ^0.5.0;

import './interfaces/ISHIBSCSwapFactory.sol';
import './SHIBSCSwapPair.sol';

contract SHIBSCSwapFactory is ISHIBSCSwapFactory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;
    bytes32 public pairCreationCodeHash;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
        pairCreationCodeHash = keccak256(abi.encodePacked(type(SHIBSCSwapPair).creationCode));
    }

    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'SHIBSCSwap: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'SHIBSCSwap: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'SHIBSCSwap: PAIR_EXISTS');
        // single check is sufficient
        bytes memory bytecode = type(SHIBSCSwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        ISHIBSCSwapPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function calcPair(address tokenA, address tokenB) external view returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'SHIBSCSwap: ZERO_ADDRESS');
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        /*
        create2(v, p, n, s)
        create new contract with code mem[p…(p+n)) at address
        keccak256(0xff . this . s . keccak256(mem[p…(p+n)))
        and send v wei and return the new address, where 0xff is a 1 byte value,
        this is the current contract’s address as a 20 byte value and s is a big-endian
        256-bit value
        */
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                address(this),
                salt,
                pairCreationCodeHash
            ))));
        return address(pair);
    }

    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'SHIBSCSwap: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'SHIBSCSwap: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
