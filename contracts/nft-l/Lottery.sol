// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./LotteryNFT.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// import "@nomiclabs/buidler/console.sol";

// 4 numbers
contract Lottery is Ownable, Initializable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 constant PERCENT = 100;

    /*   4      3      2
        C4  +  C4  +  C4  =  1 + 4 + 6 = 11
    */
    //uint8 constant keyLengthForEachBuy = 11;

    /*   4
        C4 = 1
    */
    // Allocation for win/lose
    uint8[2] public allocation;
    // The TOKEN to buy lottery
    IERC20 public shibsc;
    // The Lottery NFT for tickets
    LotteryNFT public lotteryNFT;

    // maxNumber
    uint8 public maxNumber;//0 for null, 1,2,3,4,5 for 5 choice
    // minPrice, if decimal is not 18, please reset it
    uint256 public ticketPrice;
    uint256 public burnProportion;//burn proportion from ticket
    uint256 public claimFee;
    // =================================

    // issueId => winningNumbers[numbers]
    mapping(uint256 => uint8[4]) public historyNumbers;
    // issueId => [tokenId]
    mapping(uint256 => uint256[]) public lotteryInfo;
    // issueId => [totalAmount, win]
    mapping(uint256 => uint256[]) public historyAmount;
    // issueId => the 4th number(in only full-match case, that's identical) => how many token ids
    mapping(uint256 => mapping(uint256 => uint256)) public history4thNumberTokenIds;

    // issueId => ticketNumberIndex => buyAmountSum
    mapping(uint256 => mapping(uint64 => uint256)) public userBuyAmountSum;
    // address => [tokenId]
    mapping(address => uint256[]) public userInfo;
    // address => issueIndex => [tokenId]
    mapping(address => mapping(uint256 => uint256[])) public userInfoByIssueIndex;

    uint256 public issueIndex = 0;
    uint256 public totalBoughtAddresses = 0;
    //total bought shibsc
    uint256 public totalBoughtAmount = 0;
    uint256 public lastTimestamp;
    uint256 public totalBurn = 0;

    uint8[4] public winningNumbers;

    // default false
    bool public drawingPhase;
    uint256 public currentIssueIndexStartTime = 0;
    address public burnAddress;

    address internal feeManager;
    // =================================

    //e3d4187f6ca4248660cc0ac8b8056515bac4a8132be2eca31d6d0cc170722a7e
    event Buy(address indexed user, uint256 tokenId);
    event Drawing(uint256 indexed issueIndex, uint8[4] winningNumbers);
    event Claim(address indexed user, uint256 tokenid, uint256 amount);
    event TransferBack(address token, address to, uint256 amount);
    event Reset(uint256 indexed issueIndex);
    event MultiClaim(address indexed user, uint256 amount);
    event MultiBuy(address indexed user, uint256 amount);

    constructor(
        IERC20 _shibsc,
        LotteryNFT _lottery,
        uint256 _ticketPrice,
        uint8 _maxNumber,
        uint8[2] memory _allocation,
        address _burnAddress,
        address _feeManager,
        uint256 _burnProportion
    ) public {
        shibsc = _shibsc;
        lotteryNFT = _lottery;
        ticketPrice = _ticketPrice;
        maxNumber = _maxNumber;
        lastTimestamp = block.timestamp;
        allocation = _allocation;
        currentIssueIndexStartTime = block.timestamp;
        burnAddress = _burnAddress;
        burnProportion = _burnProportion;
        claimFee = 0.000 ether;
        feeManager = _feeManager;
    }


    uint8[4] private nullTicket = [0, 0, 0, 0];

    modifier inDrawingPhase() {
        require(!drawed(), 'drawed, can not buy now');
        require(!drawingPhase, 'drawing, can not buy now');
        _;
    }

    function drawed() public view returns (bool) {
        return winningNumbers[0] != 0;
    }

    //3
    function reset() public onlyOwner {
        require(drawed(), "drawed?");
        lastTimestamp = block.timestamp;
        totalBoughtAddresses = 0;
        totalBoughtAmount = 0;
        winningNumbers[0] = 0;
        winningNumbers[1] = 0;
        winningNumbers[2] = 0;
        winningNumbers[3] = 0;
        drawingPhase = false;
        issueIndex = issueIndex + 1;

        uint256 lastRoundTotalRewards = getTotalRewards(issueIndex - 1);

        uint256 leftAmount = 0;

        if (getWinRewardAmount(issueIndex - 1) == 0) {//no one wins
            leftAmount = leftAmount.add(lastRoundTotalRewards.mul(allocation[0]).div(100));
        }


        leftAmount = leftAmount.add(lastRoundTotalRewards.mul(allocation[1]).div(100));

        uint256 burnAmount = leftAmount.mul(burnProportion).div(100);
        uint256 handoverAmount = leftAmount.sub(burnAmount);

        if (burnAmount > 0) {
            burnTickets(burnAmount);
        }

        if (handoverAmount > 0) {
            internalBuy(handoverAmount, nullTicket);
        }

        currentIssueIndexStartTime = block.timestamp;
        emit Reset(issueIndex);
    }

    //1
    function enterDrawingPhase() public onlyOwner {
        require(!drawed(), 'drawed');
        drawingPhase = true;
    }

/*    //only for test
    function drawingCheat(uint256 n4) public onlyOwner {
        require(!drawed(), "reset?");
        require(drawingPhase, "enter drawing phase first");

        // 1
        winningNumbers[0] = uint8(1);

        // 2
        winningNumbers[1] = uint8(1);

        // 3
        winningNumbers[2] = uint8(1);

        // 4
        winningNumbers[3] = uint8(n4);

        historyNumbers[issueIndex] = winningNumbers;
        historyAmount[issueIndex] = calculateMatchingRewardAmount();
        drawingPhase = false;
        emit Drawing(issueIndex, winningNumbers);
    }*/


    //2
    // add externalRandomNumber to prevent node validators exploiting
    function drawing(uint256 _externalRandomNumber) public onlyOwner {
        require(!drawed(), "reset?");
        require(drawingPhase, "enter drawing phase first");
        bytes32 _structHash;
        uint256 _randomNumber;
        uint8 _maxNumber = maxNumber;
        bytes32 _blockhash = blockhash(block.number - 1);

        // waste some gas fee here
        for (uint i = 0; i < 10; i++) {
            getTotalRewards(issueIndex);
        }
        uint256 gasLeft = gasleft();


        winningNumbers[0] = uint8(1);

        winningNumbers[1] = uint8(1);

        winningNumbers[2] = uint8(1);

        // 4
        _structHash = keccak256(
            abi.encode(
                _blockhash,
                gasLeft,
                _externalRandomNumber
            )
        );
        _randomNumber = uint256(_structHash);
        assembly {_randomNumber := add(mod(_randomNumber, _maxNumber), 1)}
        winningNumbers[3] = uint8(_randomNumber);

        historyNumbers[issueIndex] = winningNumbers;
        historyAmount[issueIndex] = calculateMatchingRewardAmount();
        drawingPhase = false;
        emit Drawing(issueIndex, winningNumbers);
    }

    function oneClickDraw(uint256 _externalRandomNumber) external onlyOwner {
        enterDrawingPhase();
        drawing(_externalRandomNumber);
        reset();
    }

/*    function oneClickDrawCheat(uint256 n4) external onlyOwner {
        enterDrawingPhase();
        drawingCheat(n4);
        reset();
   }*/

    function internalBuy(uint256 _price, uint8[4] memory _numbers) internal {
        require(!drawed(), 'drawed, can not buy now');
        for (uint i = 0; i < 4; i++) {
            require(_numbers[i] <= maxNumber, 'exceed the maximum');
        }
        uint256 tokenId = lotteryNFT.newLotteryItem(address(this), _numbers, _price, issueIndex);
        lotteryInfo[issueIndex].push(tokenId);
        totalBoughtAmount = totalBoughtAmount.add(_price);
        //no need for userBuyAmountSum
        lastTimestamp = block.timestamp;
        emit Buy(address(this), tokenId);

    }

    function emptyBuy(uint256 _price) external inDrawingPhase {
        shibsc.safeTransferFrom(address(msg.sender), address(this), _price);
        internalBuy(_price, nullTicket);
    }

    function buy(uint256 _price, uint8[4] memory _tickectNumbers) public inDrawingPhase {
        require(_price >= ticketPrice, 'price must be large than or equal to minPrice');
        for (uint i = 0; i < 4; i++) {
            require(_tickectNumbers[i] <= maxNumber && _tickectNumbers[i] > 0, 'exceed number scope');
        }

        uint256 balanceBefore = shibsc.balanceOf(address(this));
        shibsc.safeTransferFrom(address(msg.sender), address(this), _price);
        uint256 balanceAfter = shibsc.balanceOf(address(this));

        //token may deduce after transfer
        _price = balanceAfter.sub(balanceBefore);

        uint256 tokenId = lotteryNFT.newLotteryItem(msg.sender, _tickectNumbers, _price, issueIndex);
        lotteryInfo[issueIndex].push(tokenId);
        if (userInfo[msg.sender].length == 0) {
            totalBoughtAddresses = totalBoughtAddresses + 1;
        }
        userInfo[msg.sender].push(tokenId);
        userInfoByIssueIndex[msg.sender][issueIndex].push(tokenId);
        totalBoughtAmount = totalBoughtAmount.add(_price);

        lastTimestamp = block.timestamp;
        /*uint64[keyLengthForEachBuy] memory userNumberIndex = generateNumberIndexKey(_tickectNumbers);
        for (uint i = 0; i < keyLengthForEachBuy; i++) {
            userBuyAmountSum[issueIndex][userNumberIndex[i]] = userBuyAmountSum[issueIndex][userNumberIndex[i]].add(_price);
        }*/
        uint64 userNumberIndex = generateNumberIndexKey(_tickectNumbers);
        userBuyAmountSum[issueIndex][userNumberIndex] = userBuyAmountSum[issueIndex][userNumberIndex].add(_price);

        history4thNumberTokenIds[issueIndex][_tickectNumbers[3]] = history4thNumberTokenIds[issueIndex][_tickectNumbers[3]].add(1);

        emit Buy(msg.sender, tokenId);
    }

    function multiBuy(uint256[] memory _price, uint8[4][] memory _ticketNumbers) public {
        require(_price.length == _ticketNumbers.length, "_price.length == _ticketNumbers.length");
        for (uint256 i = 0; i < _price.length; i++) {
            buy(_price[i], _ticketNumbers[i]);
        }
    }

    //claim need charge ht
    function claimReward(uint256 _tokenId) external payable {
        require(msg.sender == lotteryNFT.ownerOf(_tokenId), "not from owner");
        require(!lotteryNFT.getClaimStatus(_tokenId), "claimed");

        require(msg.value >= claimFee, "claim fee?");
        payable(feeManager).transfer(msg.value);

        uint256 reward = getRewardView(_tokenId);
        lotteryNFT.claimReward(_tokenId);
        if (reward > 0) {
            shibsc.safeTransfer(address(msg.sender), reward);
        }
        emit Claim(msg.sender, _tokenId, reward);
    }

    function multiClaim(uint256[] memory _tickets) external payable {
        uint256 totalReward = 0;
        uint256 number = _tickets.length;

        require(number <= 5, "you cannot multi-claim more than 5 tickets due to gas explosion");

        require(msg.value >= number * claimFee, "claim fee?");
        payable(feeManager).transfer(msg.value);

        for (uint i = 0; i < _tickets.length; i++) {
            require(msg.sender == lotteryNFT.ownerOf(_tickets[i]), "not from owner");
            require(!lotteryNFT.getClaimStatus(_tickets[i]), "claimed");
            uint256 reward = getRewardView(_tickets[i]);
            if (reward > 0) {
                totalReward = reward.add(totalReward);
            }
        }
        lotteryNFT.multiClaimReward(_tickets);
        if (totalReward > 0) {
            shibsc.safeTransfer(address(msg.sender), totalReward);
        }
        emit MultiClaim(msg.sender, totalReward);
    }

    function generateNumberIndexKey(uint8[4] memory ticketNumber) public pure returns (uint64) {
        uint64[4] memory tempNumber;
        tempNumber[0] = uint64(ticketNumber[0]);
        tempNumber[1] = uint64(ticketNumber[1]);
        tempNumber[2] = uint64(ticketNumber[2]);
        tempNumber[3] = uint64(ticketNumber[3]);

        uint64 result;
        result = tempNumber[0] * 256 * 256 * 256 * 256 * 256 * 256 + 1 * 256 * 256 * 256 * 256 * 256 + tempNumber[1] * 256 * 256 * 256 * 256 + 2 * 256 * 256 * 256 + tempNumber[2] * 256 * 256 + 3 * 256 + tempNumber[3];

        /*        //0,1,2
                result[1] = tempNumber[0] * 256 * 256 * 256 * 256 + 1 * 256 * 256 * 256 + tempNumber[1] * 256 * 256 + 2 * 256 + tempNumber[2];
                //0,1,3
                result[2] = tempNumber[0] * 256 * 256 * 256 * 256 + 1 * 256 * 256 * 256 + tempNumber[1] * 256 * 256 + 3 * 256 + tempNumber[3];
                //0,2,3
                result[3] = tempNumber[0] * 256 * 256 * 256 * 256 + 2 * 256 * 256 * 256 + tempNumber[2] * 256 * 256 + 3 * 256 + tempNumber[3];
                //1,2,3
                result[4] = 1 * 256 * 256 * 256 * 256 * 256 + tempNumber[1] * 256 * 256 * 256 * 256 + 2 * 256 * 256 * 256 + tempNumber[2] * 256 * 256 + 3 * 256 + tempNumber[3];

                //0,1
                result[5] = tempNumber[0] * 256 * 256 + 1 * 256 + tempNumber[1];
                //0,2
                result[6] = tempNumber[0] * 256 * 256 + 2 * 256 + tempNumber[2];
                //0,3
                result[7] = tempNumber[0] * 256 * 256 + 3 * 256 + tempNumber[3];
                //1,2
                result[8] = 1 * 256 * 256 * 256 + tempNumber[1] * 256 * 256 + 2 * 256 + tempNumber[2];
                //1,3
                result[9] = 1 * 256 * 256 * 256 + tempNumber[1] * 256 * 256 + 3 * 256 + tempNumber[3];
                //2,3
                result[10] = 2 * 256 * 256 * 256 + tempNumber[2] * 256 * 256 + 3 * 256 + tempNumber[3];*/

        return result;
    }

    function burnTickets(uint256 amount) internal {
        totalBurn += amount;
        shibsc.safeTransfer(burnAddress, amount);
    }

    function calculateMatchingRewardAmount() internal view returns (uint256[2] memory) {
        //中奖票->index
        uint64 numberIndexKey = generateNumberIndexKey(winningNumbers);

        uint256 totalAmount1 = userBuyAmountSum[issueIndex][numberIndexKey];

        return [totalBoughtAmount, totalAmount1];
    }

    function getWinRewardAmount(uint256 _issueIndex) public view returns (uint256) {
        // issueId => [totalAmount, win]
        return historyAmount[_issueIndex][1];
    }

    function getTotalRewards(uint256 _issueIndex) public view returns (uint256) {
        require(_issueIndex <= issueIndex, '_issueIndex <= issueIndex');

        if (!drawed() && _issueIndex == issueIndex) {
            return totalBoughtAmount;
        }
        // issueId => [totalAmount, win]
        return historyAmount[_issueIndex][0];
    }

    function getRewardView(uint256 _tokenId) public view returns (uint256) {
        uint256 _issueIndex = lotteryNFT.getLotteryIssueIndex(_tokenId);
        uint8[4] memory lotteryNumbers = lotteryNFT.getLotteryNumbers(_tokenId);
        uint8[4] memory _winningNumbers = historyNumbers[_issueIndex];
        require(_winningNumbers[0] != 0, "not drawed");

        bool win = _winningNumbers[0] == lotteryNumbers[0]
        && _winningNumbers[1] == lotteryNumbers[1]
        && _winningNumbers[2] == lotteryNumbers[2]
        && _winningNumbers[3] == lotteryNumbers[3];


        uint256 reward = 0;
        if (win) {
            uint256 amount = lotteryNFT.getLotteryAmount(_tokenId);
            uint256 poolAmount = getTotalRewards(_issueIndex).mul(allocation[0]).div(100);
            reward = uint256(1e18).mul(amount).div(getWinRewardAmount(_issueIndex)).mul(poolAmount);
        }
        return reward.div(1e18);
    }

    //be sure you have maximal gaslimit
    function getTickets(address someone, uint256 _issueIndex) public view returns (uint8[4][] memory){
        uint8[4][] memory ret = new uint8[4][](userInfoByIssueIndex[someone][_issueIndex].length);

        for (uint256 i = 0; i < userInfoByIssueIndex[someone][_issueIndex].length; i++) {
            uint256 tokenId = userInfoByIssueIndex[someone][_issueIndex][i];
            uint8[4] memory tokenNumber = lotteryNFT.getLotteryNumbers(tokenId);
            ret[i] = tokenNumber;
        }
        return ret;
    }

    function transferBack(IERC20 erc20Token, address to, uint256 amount) external onlyOwner {
        if (address(erc20Token) == address(0)) {
            payable(to).transfer(amount);
        } else {
            erc20Token.safeTransfer(to, amount);
        }
        emit TransferBack(address(erc20Token), to, amount);
    }

    // Set the minimum price for one ticket
    function setTicketPrice(uint256 _price) external onlyOwner {
        ticketPrice = _price;
    }

    // Set the minimum price for one ticket
    function setMaxNumber(uint8 _maxNumber) external onlyOwner {
        maxNumber = _maxNumber;
    }

    // Set the allocation for one reward
    function setAllocation(uint8 _allocation1, uint8 _allocation2) external onlyOwner {
        require(_allocation1 + _allocation2 == 100, 'not equal 100');
        allocation = [_allocation1, _allocation2];
    }

    function setBurnAddressAndProportion(address _burnAddress, uint256 _burnProportion) external onlyOwner {
        burnAddress = _burnAddress;
        burnProportion = _burnProportion;
    }

    function changeClaimFee(uint256 _claimFee) external onlyOwner {
        claimFee = _claimFee;
    }

}
