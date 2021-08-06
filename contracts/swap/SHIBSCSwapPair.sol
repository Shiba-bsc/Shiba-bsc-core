pragma solidity ^0.5.0;

import './interfaces/ISHIBSCSwapPair.sol';
import './SHIBSCSwapERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/ISHIBSCSwapFactory.sol';
import './interfaces/ISHIBSCSwapCallee.sol';

contract SHIBSCSwapPair is ISHIBSCSwapPair, SHIBSCSwapERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10 ** 3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'SHIBSCSwap: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'SHIBSCSwap: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() public {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'SHIBSCSwap: FORBIDDEN');
        // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    //设定balance(新) -> reserve(旧)
    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(- 1) && balance1 <= uint112(- 1), 'SHIBSCSwap: OVERFLOW');
        //每次新的block有mint,burn和swap的时候,都要更新blockTimestampLast,price0CumulativeLast和price1CumulativeLast
        //为了服务oracle
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            //timeElapsed大于0意味着在这笔tx发生的block上,这是第一次更新
            //用旧的值!!!!
            //_reserve1 * 2^112  /   _reserve0, 所以真实使用的时候需要除以 2^112
            //price0CumulativeLast is uint224!!!!
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        //reserve更新为最新的balanced
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k), 也就是3/1000 的 1/6 0.5/1000
    // 只有在mint和burn的时候才会调用
    // swap的时候不调用
    // 每次mint和burn的时候,都会将liquidity额外膨胀,达到1/6的手续费给feeTo
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = ISHIBSCSwapFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast;
        // gas savings
        //feeTo = 0x00
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    /*
                                                     (rootK - rootKLast)
                        liquidity = totalSupply * ----------------------------- 定比分点公式, 1:5
                                                     (rootK * 5) + rootKLast
                    */
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    // 如果feeTo打开 那么给feeto mint 1/6 的fee??
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    //owner必须先将token转入到pair名下
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        // gas savings
        //已经完成了转账,所以balance0和balance1都是最新的
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));
        //充值的token数量
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);

        //feeOn = false
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply;
        // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            //liquidity = sqrt(amount0*amount1) - 1000
            //其中的1000是分配给address(0)的固定MINIMUM_LIQUIDITY
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY);
            // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            //liquidity = amount0/reserve0*totalSupply 或者 amount1/reserve1*totalSuppl 中小的的那个
            //liquidity = 以 充值token的数量 与 当前已经有的token数量的比例 增发 LPT(totalSupply)
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'SHIBSCSwap: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);

        //设定balance(新) -> reserve(旧)
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1);
        // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    //根据当前的x/y的比例, 根据被转移到自身的liquidity和totalSupply的比例,返回amount
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        // gas savings
        address _token0 = token0;
        // gas savings
        address _token1 = token1;
        // gas savings
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        // uint liquidity = balanceOf[to] ?
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply;
        // gas savings, must be defined here since totalSupply can update in _mintFee
        //amount = liquidity/totalSupply * balance
        //amount = 以 提取liquidity的数量 与 当前所有liquidity(totalSupply)数量的比例 销毁 token(balance)
        amount0 = liquidity.mul(balance0) / _totalSupply;
        // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply;
        // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'SHIBSCSwap: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        //设定balance(新) -> reserve(旧)
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1);
        // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks
    //out = swap 给出的token
    //in = swap 想要兑换的目标的数量
    // to 必须事先把token转到pair名下
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        require(amount0Out > 0 || amount1Out > 0, 'SHIBSCSwap: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'SHIBSCSwap: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        {// scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, 'SHIBSCSwap: INVALID_TO');
            //向to transfer对应数量的token的amount
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
            // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
            // optimistically transfer tokens
            //ISHIBSCSwapCallee 是方便 FlashSwap
            if (data.length > 0) ISHIBSCSwapCallee(to).dcswapCall(msg.sender, amount0Out, amount1Out, data);
            //balance是已经经过转账后的的最新数据了,to可能已经把token先转入,随后pair又有转出
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'SHIBSCSwap: INSUFFICIENT_INPUT_AMOUNT');
        {// scope for reserve{0,1}Adjusted, avoids stack too deep errors
            //只要有amount in就要交手续费 交易费是3/1000
            uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
            uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
            //扣除3%的手续费,计算K
            //swap其实只是验证K
            require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000 ** 2), 'SHIBSCSwap: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0;
        // gas savings
        address _token1 = token1;
        // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
