pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./BasicNFT.sol";

//equipment include ethnic
contract Pet is ERC721, Ownable {
    using SafeMath for uint256;

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    //current available equipments
    // the first is main equipment and must have some equipment equipped
    //第一个BasicNFT必须是唯一的,作为身份id,因为一个地址只能拥有1个pet
    BasicNFT[] public availableEquipments;

    //player => body part => equipment token Id
    mapping(address => mapping(BasicNFT => uint256)) equipments;

    constructor () public ERC721( "SHIBSC PET","SHIBSC-PET"){
    }

    modifier ready(){
        require(availableEquipments.length > 0, "availableEquipments.length");
        _;
    }

    //every address could have only one pet

    //you should some how to get a main equipment at first
    //one player could only create one pet
    function newItem(uint256 mainEquipmentsTokenId,address player) ready external {

        require(balanceOf(player) == 0, "you can not create more than one pet");

        //starts from 1
        _tokenIds.increment();

        uint256 newId = _tokenIds.current();
        _mint(player, newId);



        require(mainEquipmentsTokenId != 0, "main equipment must not be empty");

        require(availableEquipments[0].ownerOf(mainEquipmentsTokenId) == msg.sender, "main equipment must be msg.sender");

        equipments[msg.sender][availableEquipments[0]] = mainEquipmentsTokenId;
    }

    function equip(BasicNFT[] memory parts, uint256[] memory tokenIds) ready external {
        require(parts.length == tokenIds.length, "parts.length == tokenIds.length");
        for (uint256 i = 0; i < parts.length; i++) {
            require(parts[i].ownerOf(tokenIds[i]) == msg.sender, "equipment must be msg.sender");
            equipments[msg.sender][parts[i]] = tokenIds[i];
        }
    }


    function getProperty(address player) ready external returns (uint256 lifeAcc, uint256 attackAcc, uint256 defenseAcc, uint256 evadeAcc, uint256 criticalAcc, uint256 levelAcc){
        lifeAcc = 0;
        attackAcc = 0;
        defenseAcc = 0;
        evadeAcc = 0;
        criticalAcc = 0;
        levelAcc = 0;
        for (uint256 i = 0; i < availableEquipments.length; i ++) {


            uint256 tokenId = equipments[player][availableEquipments[i]];
            if (tokenId == 0) {
                if (i == 0) {
                    revert("main equipment must exist");
                }
                continue;
            }
            (uint256 life, uint256 attack, uint256 defense, uint256 evade, uint256 critical, uint256 level) = availableEquipments[i].getProperty(tokenId);

            lifeAcc = lifeAcc.add(life);
            attackAcc = attackAcc.add(attack);
            defenseAcc = defenseAcc.add(defense);
            evadeAcc = evadeAcc.add(evade);
            criticalAcc = criticalAcc.add(critical);
            levelAcc = levelAcc.add(level);

        }
        return (lifeAcc, attackAcc, defenseAcc, evadeAcc, criticalAcc, levelAcc);
    }

}
