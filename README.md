# DailyDose
This is a basic elimination style game that works on Ethereum. 

Essentially players pay a tiered price for an entry NFT into the game. All the money collected goes into the vault.

Once the game has begun players are must click a button on the connected website/send a transaction to this contract everyday. This task burns their previous days NFT for a new one. If a player fails to complete this task they are eliminated from the game. 

There are two ways to win the game:

A solo win occurs when only 1 player minted the previous NFT and is therefore the only one left playing the game

A group when occurs when collectively the group decides to not mint the next NFT. If they can successfully have multiple mints on day “n” and exactly 0 mints on day “n+1”, then one day “n+2” all those who minted on day n will be able to claim their share of the vault. 

The winner(s) are able to claim their share of the vault (#ETH/# of winners)
