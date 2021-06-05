// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import "./uniswap/IUniswapV2Pair.sol";
import "./uniswap/IUniswapV2Factory.sol";
import "./uniswap/UQ112x112.sol";

/*
Note: 0.6.0 and 0.7.0 won't use overflow wrapping unlike 0.8.0
*/
contract ShibscOracle is Ownable {
    using SafeMath for uint256;
    using UQ112x112 for uint224;

    //assume bsc and heco produce block every approx. 3 seconds
    // 15 minutes = 900 seconds = 300 blocks
    // 512 blocks should be enough for at most 15 minutes record
    uint256 constant LENGTH = 2 ** 9;
    //uint256 constant LENGTH = 2 ** 3;//for test purpose

    address public factory;

    enum PriceMode{
        LastEffective18, //0
        LastEffective112,
        OneMinute18,
        OneMinute112,
        FiveMinutes18,
        FiveMinutes112,
        FifteenMinutes18,
        FifteenMinutes112
    }

    bool public serviceAvailable;

    //63f32f63810afda7c9be9643f9fa73ee3f39a9fd8bb35775a2b0d73e48ed9bed
    event Price(uint256 price);

    //ad7c87b11456fab3d69245f95442061bce96cb3c345293507ec8bae59023990f
    //event Debug(uint256 mark, uint256 amount);


    constructor(address _factory) public {
        factory = _factory;
        serviceAvailable = true;
    }

    /*
    we have 3 prices:
    1: average price of last 1 minutes if possible
    2: average price of last 5 minutes if possible
    3: average price of last 15 minutes if possible
    */

    struct Record {
        address pair;
        address token0;//usdt
        address token1;//wbnb

        //token1/token0
        uint224[LENGTH] price0;
        //token0/token1
        uint224[LENGTH] price1;// wbnb price
        uint32[LENGTH] timestamp;

        uint16 pointer1; //2^16 = 65536 is enough for LENGTH = 512, which could compact struct and save a little gas
        uint16 pointer5;
        uint16 pointer15;
        uint16 pointerTail;
    }

    mapping(address => mapping(address => Record)) records;

    function getRecordSummary(address quote, address base) external view returns (address pair, address token0, address token1, uint16 pointer1, uint16 pointer5, uint16 pointer15, uint16 pointerTail){
        (address token0,address token1) = sortTokens(quote, base);
        Record storage record = records[token0][token1];
        return (record.pair, record.token0, record.token1, record.pointer1, record.pointer5, record.pointer15, record.pointerTail);
    }

    function getRecordDetail(address quote, address base, uint256 cursor) external view returns (uint224 price0, uint224 price1, uint32 timestamp){
        (address token0,address token1) = sortTokens(quote, base);
        Record storage record = records[token0][token1];
        return (record.price0[cursor], record.price1[cursor], record.timestamp[cursor]);
    }

    //init(if need), update, calc
    function getPrice(address quote, address base, PriceMode mode) external returns (uint256){

        if(!serviceAvailable){
            return 0;
        }

        (address token0,address token1) = sortTokens(quote, base);
        Record storage record = records[token0][token1];
        if (record.token0 == address(0)) {
            init(record, token0, token1);
        }

        updateRecord(record);

        updatePointer(record);
        //revert("test");

        bool isPrice0 = false;
        if (quote == token0) {
            //price0
            isPrice0 = true;
        } else {
            //price1
            isPrice0 = false;
        }

        uint256 price = 0;
        if (mode == PriceMode.LastEffective18 || mode == PriceMode.LastEffective112) {
            price = calcPriceLastEffective(record, mode, isPrice0);
        } else {
            price = calcPrice(record, mode, isPrice0);
        }

        emit Price(price);
        return price;
    }

    function calcPriceLastEffective(Record storage record, PriceMode mode, bool isPrice0) internal returns (uint256){

        if (mode == PriceMode.LastEffective18 || mode == PriceMode.LastEffective112) {

        } else {
            revert("unknown PriceMode2");
        }

        uint16 pointerTail = record.pointerTail;
        uint32 timestampTail = record.timestamp[pointerTail];

        uint16 pointerPrevious = pointerRetreat(pointerTail);
        uint32 timestampPrevious = record.timestamp[pointerPrevious];

        if (timestampPrevious == uint32(0)) {
            //not enough record, you are at very begin
            return 0;
        }

        uint224 price = 0;
        if (isPrice0) {

            price = (record.price0[pointerTail] - record.price0[pointerPrevious]) / (timestampTail - timestampPrevious);
        } else {
            price = (record.price1[pointerTail] - record.price1[pointerPrevious]) / (timestampTail - timestampPrevious);
        }

        if (mode == PriceMode.LastEffective18) {
            //2^224 * 2^30(<10^9) = 2^254 won't overflow
            return uint256(price).mul(10 ** 9).div(2 ** 56).mul(10 ** 9).div(2 ** 56);
        } else if (mode == PriceMode.LastEffective112) {
            return uint256(price);
        } else {
            revert("unknown PriceMode2");
        }
    }

    function calcPrice(Record storage record, PriceMode mode, bool isPrice0) internal returns (uint256){

        uint16 pointerTail = record.pointerTail;
        uint32 timestampTail = record.timestamp[pointerTail];

        uint16 pointerX;
        uint32 interval;
        if (mode == PriceMode.OneMinute18 || mode == PriceMode.OneMinute112) {
            pointerX = record.pointer1;
            interval = uint32(1 minutes);
        } else if (mode == PriceMode.FiveMinutes18 || mode == PriceMode.FiveMinutes112) {
            pointerX = record.pointer5;
            interval = uint32(5 minutes);

        } else if (mode == PriceMode.FifteenMinutes18 || mode == PriceMode.FifteenMinutes112) {
            pointerX = record.pointer15;
            interval = uint32(15 minutes);

        } else {
            revert("unknown PriceMode");
        }


        //find the nearest pointer and check if need average calc
        //pointerX is always less than or equal to pointerTail
        if (pointerX == pointerTail) {
            //not enough record
            return 0;
        }


        if (timestampTail - record.timestamp[pointerX] < interval) {
            //not enough records, should return 0;
            return 0;
        }

        uint16 pointerNext = pointerAdvance(pointerX);

        uint32 timeStart = timestampTail - interval;

        uint224 price = 0;
        if (isPrice0) {
            uint224 priceStart = record.price0[pointerX] +
            (timeStart - record.timestamp[pointerX]) *
            (record.price0[pointerNext] - record.price0[pointerX]) /
            (record.timestamp[pointerNext] - record.timestamp[pointerX]);


            price = (record.price0[pointerTail] - priceStart) / interval;
        } else {
            uint224 priceStart = record.price1[pointerX] +
            (timeStart - record.timestamp[pointerX]) *
            (record.price1[pointerNext] - record.price1[pointerX]) /
            (record.timestamp[pointerNext] - record.timestamp[pointerX]);

            price = (record.price1[pointerTail] - priceStart) / interval;

        }

        if (mode == PriceMode.OneMinute18 || mode == PriceMode.FiveMinutes18 || mode == PriceMode.FifteenMinutes18) {
            //2^224 * 2^30(<10^9) = 2^254 won't overflow
            return uint256(price).mul(10 ** 9).div(2 ** 56).mul(10 ** 9).div(2 ** 56);
        } else if (mode == PriceMode.OneMinute112 || mode == PriceMode.FiveMinutes112 || mode == PriceMode.FifteenMinutes112) {
            return uint256(price);
        } else {
            revert("unknown PriceMode");
        }

    }

    function updatePointer(Record storage record) internal {

        //the last record's timestamp must be "now" cause we insert if necessary
        //the tail is at now after "insert"
        uint16 pointerTail = record.pointerTail;
        uint32 timestampTail = record.timestamp[pointerTail];

        {
            uint16 pointer1 = record.pointer1;
            while (pointer1 != pointerTail) {

                //if the next possible record is still fine, move pointer forward
                uint16 next = pointerAdvance(pointer1);
                if (next == pointerTail) {
                    //no more record, break
                    break;
                }
                uint32 timestampNext = record.timestamp[next];

                //if not, this is a fatal bug
                require(timestampTail > timestampNext, "timestampTail > timestampNext");

                if (timestampTail - timestampNext >= uint32(1 minutes)) {
                    pointer1 = next;
                } else {
                    break;
                }
            }
            record.pointer1 = pointer1;
        }

        {
            uint16 pointer5 = record.pointer5;
            while (pointer5 != pointerTail) {

                //if the next possible record is still fine, move pointer forward
                uint16 next = pointerAdvance(pointer5);
                if (next == pointerTail) {
                    //no more record, break
                    break;
                }
                uint32 timestampNext = record.timestamp[next];

                //if not, this is a fatal bug
                require(timestampTail > timestampNext, "timestampTail > timestampNext");

                if (timestampTail - timestampNext >= uint32(5 minutes)) {
                    pointer5 = next;
                } else {
                    break;
                }
            }
            record.pointer5 = pointer5;
        }

        {
            uint16 pointer15 = record.pointer15;
            while (pointer15 != pointerTail) {

                //if the next possible record is still fine, move pointer forward
                uint16 next = pointerAdvance(pointer15);
                if (next == pointerTail) {
                    //no more record, break
                    break;
                }
                uint32 timestampNext = record.timestamp[next];

                //if not, this is a fatal bug
                require(timestampTail > timestampNext, "timestampTail > timestampNext");

                if (timestampTail - timestampNext >= uint32(15 minutes)) {
                    pointer15 = next;
                } else {
                    break;
                }
            }
            record.pointer15 = pointer15;
        }


    }

    function updateRecord(Record storage record) internal {
        //if the current timestamp exceed the timestamp of latest record, we use the current price to mock and insert record
        //actually, the reserve0 and reserve1 is cached and it promise it shall update cumulative price before update reserves
        //before very first tx of block. thus reserve1/reserve0 is the right and safe price

        uint32 lastTimestamp = record.timestamp[record.pointerTail];

        if (lastTimestamp == currentBlockTime()) {
            //already updated by either new price or insertion
            return;
        }

        //1 get the last cumulative price uniswap stores and check if it needs update
        (uint224 price0CumulativeLast, uint224 price1CumulativeLast, uint32 blockTimestampLast, uint112 reserve0,uint112 reserve1) = getCumulativePriceTimestamp(record);
        if (blockTimestampLast > lastTimestamp) {
            //whatever how many times of cumulativePrice change over blocks, we can only get the last by some calling this function
            //if there are too many blocks, have to use average to estimate
            uint16 pointerTail = stepTailPointer(record);
            record.price0[pointerTail] = price0CumulativeLast;
            record.price1[pointerTail] = price1CumulativeLast;
            record.timestamp[pointerTail] = blockTimestampLast;
        }

        //2 if we could insert records to clarify that the price keeps. this could enhance accuracy against average estimate
        lastTimestamp = record.timestamp[record.pointerTail];
        uint32 currentTimestamp = currentBlockTime();
        if (currentTimestamp > lastTimestamp) {
            //insert price
            uint16 oldPointerTail = record.pointerTail;
            uint16 pointerTail = stepTailPointer(record);
            uint32 timeElapsed = currentTimestamp - lastTimestamp;
            //record.price0[pointerTail] = record.price0[pointerTail] + uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            record.price0[pointerTail] = record.price0[oldPointerTail] + UQ112x112.encode(reserve1).uqdiv(reserve0) * uint224(timeElapsed);
            record.price1[pointerTail] = record.price1[oldPointerTail] + UQ112x112.encode(reserve0).uqdiv(reserve1) * uint224(timeElapsed);
            record.timestamp[pointerTail] = currentTimestamp;
        }
    }

    function init(Record storage record, address token0, address token1) internal {
        if (record.token0 == address(0)) {
            record.pair = getPairAddress(token0, token1);
            record.token0 = token0;
            record.token1 = token1;
            record.pointer1 = 0;
            record.pointer5 = 0;
            record.pointer15 = 0;
            record.pointerTail = 0;
            //update last cumulative price and timestamp
            (uint224 price0CumulativeLast, uint224 price1CumulativeLast, uint32 blockTimestampLast, uint112 reserve0,uint112 reserve1) = getCumulativePriceTimestamp(record);
            record.price0[record.pointerTail] = price0CumulativeLast;
            record.price1[record.pointerTail] = price1CumulativeLast;
            record.timestamp[record.pointerTail] = blockTimestampLast;
        }
    }

    function getPairAddress(address token0, address token1) internal returns (address){
        address pair = IUniswapV2Factory(factory).getPair(token0, token1);
        require(pair != address(0), "the pair does not exist");
        return pair;
    }

    //move pointerTail forward 1 step, which points to new slot waiting for updating value
    function stepTailPointer(Record storage record) internal returns (uint16 newPointerTail) {
        //under 0.6.0, the result will wrap if overflow
        newPointerTail = pointerAdvance(record.pointerTail);
        if (record.pointer1 == newPointerTail) {
            record.pointer1 = pointerAdvance(record.pointer1);
        }
        if (record.pointer5 == newPointerTail) {
            record.pointer5 = pointerAdvance(record.pointer5);
        }
        if (record.pointer15 == newPointerTail) {
            record.pointer15 = pointerAdvance(record.pointer15);
        }
        record.pointerTail = newPointerTail;
    }

    function getCumulativePriceTimestamp(Record storage record) internal returns (
        uint224 price0CumulativeLast,
        uint224 price1CumulativeLast,
        uint32 blockTimestampLast,
        uint112 reserve0,
        uint112 reserve1
    ){
        IUniswapV2Pair pair = IUniswapV2Pair(record.pair);
        //assume all pair's token0 is less than token1 as regular
        //0x5909c0d5
        price0CumulativeLast = uint224(pair.price0CumulativeLast());
        //0x5a3d5493
        price1CumulativeLast = uint224(pair.price1CumulativeLast());
        //0x0902f1ac
        (reserve0, reserve1, blockTimestampLast) = pair.getReserves();
    }

    function getRecord(address tokenA, address tokenB) view public returns (Record memory){
        (address token0,address token1) = sortTokens(tokenA, tokenB);
        return records[token0][token1];
    }

    function sortTokens(address tokenA, address tokenB) pure internal returns (address, address){
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return (token0, token1);
    }

    function currentBlockTime() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    function pointerAdvance(uint16 ptr) internal pure returns (uint16){
        uint256 ret = uint256(ptr) + 1;
        if (ret >= LENGTH) {
            ret = ret % LENGTH;
        }
        return uint16(ret);
    }


    function pointerRetreat(uint16 ptr) internal pure returns (uint16){
        if (ptr == uint16(0)) {
            return uint16(LENGTH) - 1;
        } else {
            return ptr - 1;
        }
    }

    function changeServiceAvailable(bool _serviceAvailable) external onlyOwner {
        serviceAvailable = _serviceAvailable;
    }
}
