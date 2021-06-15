# SHIBSC Price Oracle

## Goal

SHIBSC Price Oracle is designed for safety and convenience. Recently, many DeFi attacks on BSC combined with
flash-swap and fake oracle occur, and the hacker seized lots of valuable tokens.

SHIBSC Price Oracle provides easy way to get safe price of 2 tokens as long as they are registered as liquidity pair
and are listed on pancake or mdex (coming soon)

## Safety

Manipulating price of certain AMM pair is not so easy for public users, or even whales, because the tokens they hold
is less than the reserves in side of the AMM pair pool. However, 'thanks to' flash-swap, anyone could borrow a pile of
tokens and return these token with addition interest at the end of transaction. During the transaction, the borrower
are free to use the tokens anywhere except the lending AMM pool. That is to say, you can borrow some tokens from one
AMM pool and spend these tokens to manipulate the price of other pools.

As we could see, this kind of attack levered by flash-swap needs two basic requirement.

  - there are more than one pools you can borrow tokens, and the borrowed amount is enough to control the price.
  - do the attack in one transaction since you must return the borrowed tokens.

The first condition is not so hard to achieve, but the second can not be broken.

SHIBSC Price Oracle is based on the second law and obey UNISwap time-weighted average price.

SHIBSC read the latest relative safety price from the price of the latest price before any related transaction, like add and remove
liquidity, and swap. That's could eliminate the manipulated price in the middle of attack transactions due to the 2nd law.

However, that's possible to read the bad price after attack,  or attack transaction. This is time for time-weighted average price.
If certain price is attack, there should be arbitrages to balance the tokens in the market and bring the price back. If not,
the bad price keeps. In both condition, TWAP will smooth the price curve and give you enough time to reflect to the market.

There are 3 kind of preset TWAP ready to use, for 1 minute, for 5 minutes and for 15 minutes. If you concern prudently, you
can choose TWAP for 15 minutes.

## Convenience

Anyone could implement their own price oracle. SHIBSC Price Oracle provides this function on demand. You can directly read price
from our deployed contract by just say which tokens and what kind of TWAP you need.

Another benefit is you are able to save gas by share same price request with other requesters. If three smart contract read
the price in one block, the first one will pay the most gas to update necessary information and calculate TWAP. The latter
2 requester only calculate the price they need or read from cache directly. From a probabilistic sense, you should share the
heaviest update information logic with others and save lots of gas

## Future

We are planing on multi-reserve weighted price oracle and cross-chain Price Oracle as known as Data-Feed Oracle.

If the first had be implemented, price should be calculated more precisely because price data shall be based on 
simultaneously several AMM providers.

The second would be powerful for supply any data, however the transaction price is a problem.
