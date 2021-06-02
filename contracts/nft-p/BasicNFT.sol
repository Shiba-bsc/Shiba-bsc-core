pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract BasicNFT is ERC721, Ownable {
    using SafeMath for uint256;

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    struct Property {
        bool exist;
        uint256 life;
        uint256 attack;
        uint256 defense;
        uint256 evade;
        uint256 critical;

        uint256 exp;
        uint256 level;//starts from 0

        uint256 lastUpdate;//will be forcefully set by newItem()

        uint256 kind;

        uint256 lifeLU;
        uint256 attackLU;
        uint256 defenseLU;
        uint256 evadeLU;
        uint256 criticalLU;
    }

    //init config template
    // kind => Property
    mapping(uint256 => Property) propertyInitConfig;

    // tokenId => Property
    mapping(uint256 => Property) record;

    bool public unique;
    bool public transferable;
    uint256 public transferCoolDown;//0 for immediate
    mapping(uint256 => uint256) latestTransferTimestamp;

    constructor (
        string memory name_,
        string memory symbol_,
        bool unique_,
        bool transferable_,
        uint256 transferCoolDown_
    ) public ERC721(
        name_,
        symbol_
    ) {
        unique = unique_;
        transferable = transferable_;
        transferCoolDown = transferCoolDown_;
    }

    function _transfer(address from, address to, uint256 tokenId) internal override {
        require(transferable, "transferable is set to NO!");
        //if tokenId does not exist, super._transfer will reject
        require(latestTransferTimestamp[tokenId].add(transferCoolDown) <= block.timestamp, "cooling down");
        super._transfer(from, to, tokenId);
        latestTransferTimestamp[tokenId] = block.timestamp;
    }

    //one player only can have one
    function newItem(address player, uint256 kind) public onlyOwner returns (uint256)
    {

        if (unique) {
            require(balanceOf(player) == 0, "you can not create more than one equipment");
        }

        //starts from 1
        _tokenIds.increment();

        uint256 newId = _tokenIds.current();
        _mint(player, newId);

        Property storage property = propertyInitConfig[kind];
        require(property.exist, "property does not exist");

        record[newId] = property;

        record[newId].lastUpdate = block.timestamp;

        latestTransferTimestamp[newId] = block.timestamp;
        return newId;
    }

    function destroy(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "you are not owner of token");
        _burn(tokenId);
    }

    function getProperty(uint256 tokenId) external view returns (uint256 life, uint256 attack, uint256 defense, uint256 evade, uint256 critical, uint256 level){
        require(_exists(tokenId), "tokenId must exists");

        Property storage token = record[tokenId];

        return (token.life, token.attack, token.defense, token.evade, token.critical, token.level);
    }

    function levelUp(uint256 tokenId) external {
        require(_exists(tokenId), "tokenId must exists");
        require(ownerOf(tokenId) == msg.sender, "you are not owner of token");

        Property storage token = record[tokenId];

        uint256 exp = token.exp.add(block.timestamp.sub(token.lastUpdate));
        uint256 level = token.level;
        while (exp >= levelToExp(level)) {
            exp = exp.sub(levelToExp(level));
            level = level.add(1);
        }
        token.lastUpdate = block.timestamp;
    }

    function levelUpProperty(Property storage token) internal {
        token.life = token.life.add(token.lifeLU);
        token.attack = token.attack.add(token.attackLU);
        token.defense = token.defense.add(token.defenseLU);
        token.evade = token.evade.add(token.evadeLU);
        token.critical = token.critical.add(token.criticalLU);
        token.attack = token.attack.add(token.attackLU);
    }

    function levelToExp(uint256 level) internal view returns (uint256){
        return 10 hours + level * 1 hours;
    }

    function setPropertyInitConfig(uint256 kind, Property memory property) external onlyOwner {
        propertyInitConfig[kind] = property;
    }

    function setTokenProperty(uint256 tokenId, Property memory property) external onlyOwner {
        require(_exists(tokenId), "tokenId must exists");
        record[tokenId] = property;
    }

    function setTransferCoolDown(uint256 transferCoolDown_) external onlyOwner {
        transferCoolDown = transferCoolDown_;
    }
}
