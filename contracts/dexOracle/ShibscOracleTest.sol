// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./ShibscOracle.sol";

/*
Note: 0.6.0 and 0.7.0 won't use overflow wrapping unlike 0.8.0
*/
contract ShibscOracleTest {


    function callTimes(address oracle, address quote, address base, ShibscOracle.PriceMode mode, uint256 times) public {

        for (uint256 i = 0; i < times; i++) {
            ShibscOracle(oracle).getPrice(quote, base, mode);

        }
    }

    function callMods(address oracle, address quote, address base, ShibscOracle.PriceMode[] memory modes) public {
        for(uint256 i = 0; i < modes.length; i++){
            ShibscOracle(oracle).getPrice(quote, base, modes[i]);

        }
    }
}
