# Phenomenon - Become a Movement

Gain followers, defeat the nonbelievers, and smite your enemies.  Be part of the Phenomenon: the first social coordination game on the blockchain.

## Game Frontend URL
[https://0xomen.github.io/phenomenon/](https://0xomen.github.io/phenomenon/)

## Chainlink Constellation Hackathon
Phenomenon uses 2 Chainlink products: VRF and Functions.
Both of these functions can be seen in use in this repo contracts/phenomenon.sol lines 346-481.  
VRF is called when the first player registers for the game (line 188) and contract state is updated when the game starts (line 212).
Functions is called at the start of the game and any time a player takes a turn (line 216, 242, 249, 266, or 277). Starting the game exceeds the callback function gaslimit and requires a player to call setGame() to change state variables.


# Rules of Phenomenon

For 3 to 9 players

Players register to become prophets. The goal is to be the last prophet alive.

One prophet is randomly selected to be the Chose One. The Chose One has divine powers and will never fail to perform a miracle or smite another player.

No one knows who the Chose One is, not even the Chosen One. Players must deduce this through game play.

When it is a prophet's turn they can do one of three actions: Perform Miracle, Attempt to Smite, and Accuse of Blasphemy


## Perform Miracle
The Chosen One will always succeed at performing a miracle. Other players have a 75% chance of success. However, if they fail, they die. A successful miracle will free a jailed prophet.


## Attempt to Smite
A successful smite eliminates the target opponent from the game. The Chosen One will always succeed at smiting an opponent. Other players have a 10% chance of success. Chances of success increase based on the % of accolites following a prophet. There is no consequence for failing to smite an opponent.


## Accuse of Blasphemy
A successful accusation has 2 possible outcomes: if the target opponent is free, then they are placed in jail -or- if the target opponent is already in jail then they are executed and eliminated from the game. The Chosen One has no advantage with this action. Players start with a 10% chance of success and chances of success increase based on the % of accolites following a prophet. There is no consequence for failing to accuse a free opponent. The opponent is freed from jail if they are in jail and the accusal fails.



## High Priests
At the start of the game, some prophets may randomly be chosen as High Priests. These players cannot win the game on their own, however if they are the High Priest of the last remaining prophet, then the High Priest also wins. Being a High Priest improves the odds of a prophet successfully smiting an opponent or accusing them of Blasphemy. If the prophet that the High Priest is supporting dies, then the High Priest is also eliminated. High Priests may change who they support at any time (excluding the time waiting for a Chainlink Function callback) as long as they have not been eliminated.


## Ending and Reseting Game
When only one prophet remains, the winners can claim their share of the tokens in the pot. After everyone has claimed their tokens, reset the game with the desired number of players for the next round. Must wait 6 minutes to reset game. **Tokens cannot be claimed once the game is reset!!!**


## Anti-Griefing - Force Turn
If after 3 minutes a player has not taken their turn, ANYONE may force them to perform a miracle by clicking the Force Miracle button.