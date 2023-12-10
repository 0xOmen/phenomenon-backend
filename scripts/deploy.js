// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
const hre = require("hardhat")

async function main() {
    const _interval = "180"
    const _numProphets = "4"
    const _entranceFee = "100000000000000"
    const _gameToken = "0x326C977E6efc84E512bB9C30f76E30c160eD06FB" //Polygon Mumbai $LINK
    const router = "0x6E2dc0F9DB014aE19888F539E59285D2Ea04244C" //Polygon Mumbai Functions router
    const subscriptionId = "6616"
    const GameFactory = await ethers.getContractFactory("phenomenon")
    console.log("Deploying Contract....")

    const game = await GameFactory.deploy(
        _interval,
        _entranceFee,
        _numProphets,
        _gameToken,
        router,
        subscriptionId
    )

    await game.waitForDeployment()

    console.log()
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error)
    process.exitCode = 1
})
