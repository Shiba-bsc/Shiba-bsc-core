# Bunny Flash Swap Attack

1. In [first bsc tx](https://bscscan.com/tx/0x88fcffc3256faac76cde4bbd0df6ea3603b1438a5a0409b2e2b91e7c2ba3371a) attack spent a little BNBs and converted it into UsdtBnbLPv2-LPTs. Then staked LPTs into Bunny pool to be able to get reward in stage 6.
    
2. Then in [second bsc Tx](https://bscscan.com/tx/0x897c2de73dd55d7701e1b69ffb3a17b0f4801ced88b0c75fe1551c5fcce6a979) attacker borrowed 2320000BNB from 7 pancake liquidity pools and 2961750USDT from fortube via Flash Swap.

3. Attacker used borrowed 2961750 USDTs and 7744 BNBs to compose 144445 UsdtBnbLPv2-LPTs, kept in hand.

4. Attacker swapped remaining approx. 2310000 huge amount of BNBs into 3826047 USDTs via Pancake UsdtBnbLPv1 pool. 
   Now the bnb price of UsdtBnbLPv1 pool was extremely low. The attacker had controlled the BNB/USDT price of UsdtBnbLPv1 pool.

5. Attacker passed his UsdtBnbLPv2-LPT which composed in stage 3 to MinterV2, and MinterV2 decomposed UsdtBnbLPv2-LPT back into 2961750 USDTs and 7744 BNBs. And then, all 2961750 USDTs and 7744 BNBs will be transferred into BunnyBnbLPv1-LPT.

 5.1 Attacker called MinterV2, and the latter invoked ZapBsc to swap 2961750 USDTs to 2312661 BNBs via UsdtBnbLPv1.

 5.2 half of 2312661 BNBs were swapped into Bunny via BunnyBnbLPv1 and composed 105257 BunnyBnbLPv1 together with another half. The BunnyBnbLPv1's price was also be controlled since 2312661 BNBs came into pool;

 5.3 MinterV2 went on swapping half of 7744 BNBs into Bunny via BunnyBnbLPv1 and composed 351 BunnyBnbLPv1-LPT.

 5.4 Both of 105257 and 351 BunnyBnbLPv1-LPT were returned to MinterV2 and were transferred into Bunny Pool.

 5.5 Due to previous operation, there were countless BNBs in UsdtBnbLPv1 and BunnyBnbLPv1. That is to say, the BNB price is merely low to the floor, lots of BNBs could be swapped out by one USDT or one Bunny.

6. Next, bunny pool asked MinterV2 to mint certain amount of Bunnies as reward. The amount is based on Bunny price per BNB via BunnyBnbLPv1.
    Due to there had been countless BNBs in BunnyBnbLPv1, BNB price is quite low, and the BNB one Bunny worth increased thousands times, finally bunny pool minted 6972455 Bunny to Attacker.

Formula:

BunnyToMint = amount * 2 * BNBs in BunnyBnbLPv1 / amount of LPTs of BunnyBnbLPv1

amount is based on how many UsdtBnbLPv2-LPTs you had staked in stage 1
expression 2 * BNBs in BunnyBnbLPv1 / amount of LPTs of BunnyBnbLPv1 is the orthodox way to calculate bunny price over bnb
at that moment, the bnb is worthless so that BunnyToMint increased deviated to market price

7. Attacker then swapped 6972455 Bunny into BNBs and left 697246 Bunny as loot.

8. Attacker then swapped some BNBs which comes from previous operation into USDTs via UsdtBnbLPv1 leveraging the low BNB price for debt.

9. Attacker returned Flash Swap debts and received 697245 Bunny and 114631 BNB.

# Advice

Due to AMM protocol, if its pool is light, the price is vulnerable and be controlled by large token holders.

Pancake v1 has been announced deprecated and all v1 pool is reducing. Those pools are easy to attack and should be move to v2 pools.

We recommend users to use v2 pools and projects based on v2 pools and appeal to all Defi project based on Pancake v1 to upgrade to v2 protocol.
