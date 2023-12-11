let response = ""
let decryptor = 1954205708
if (secrets.decryptor) {
    decryptor = secrets.decryptor
}

const _VRFSeed = args[0]
const _numProphets = args[1]
const _action = args[2]
const _currentProphetTurn = args[3]
const _ticketShare = args[4]

// Note, largest Number to Modulo is ~16 digits, after which this will always return '0'
// We will need a very large number for encryptor to divide VRFSeed by since
// VRF is usually large
// There will need to be error catching to revert contract back to prior state
const chosenOne = Math.floor((_VRFSeed / decryptor) % _numProphets)
console.log(`chosenOne = ${chosenOne}`)

// action == 0 then attempt miracle"
if (_action == 0) {
    const miracleFailureOdds = 25
    let result = "1"
    if (_currentProphetTurn != chosenOne) {
        if (
            1 + ((Math.random() * 100) % 100) + _ticketShare / 10 <
            miracleFailureOdds
        )
            result = "0"
    }
    response = response.concat(result)
}
// action == 1 then attempt to smite
// return '3' if successful and '2' if unsuccessful
else if (_action == 1) {
    const smiteFailureOdds = 90
    let result = "3"
    if (_currentProphetTurn != chosenOne) {
        if (
            1 + ((Math.random() * 100) % 100) + _ticketShare / 2 <
            smiteFailureOdds
        )
            result = "2"
    }
    response = response.concat(result)
    // action == 2 then accuse of Blasphemy
    // return '5' if successful and '4' if unsuccessful
} else if (_action == 2) {
    const accuseFailureOdds = 90
    let result = "5"
    if (1 + ((Math.random() * 100) % 100) + _ticketShare < accuseFailureOdds) {
        result = "4"
    }
    response = response.concat(result)
}
// if action == 3 then startGame() called
else if (_action == 3) {
    for (let _prophet = 0; _prophet < _numProphets; _prophet++) {
        const miracleFailureOdds = 25
        let result = "1"
        if (_prophet != chosenOne) {
            if (1 + ((Math.random() * 100) % 100) < miracleFailureOdds)
                result = "0"
        }
        response = response.concat(result)
    }
}

return Functions.encodeString(response)
