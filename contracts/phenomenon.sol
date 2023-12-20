// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";

error Game__NotOpen();
error Game__Full();
error Game__AlreadyRegistered();
error Game__NotEnoughProphets();
error Game__NotInProgress();
error Game__ProphetIsDead();
error Game__NotAllowed();
error Game__NotEnoughTicketsOwned();
error Game__AddressIsEliminated();
error Game__ProphetNotFree();
error Game__OutOfTurn();
error Contract__OnlyOwner();
error Game__NoRandomNumber();

contract Phenomenon is FunctionsClient, ConfirmedOwner {
    string[] args;
    using FunctionsRequest for FunctionsRequest.Request;

    bytes32 public s_lastFunctionRequestId;
    bytes public s_lastFunctionResponse;
    bytes public s_lastFunctionError;
    bytes32 keyHash =
        0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
    bytes encryptedSecretsUrls;
    uint8 donHostedSecretsSlotID;
    uint64 donHostedSecretsVersion;

    error UnexpectedRequestID(bytes32 requestId);

    event Response(bytes32 indexed requestId, bytes response, bytes err);

    // Functions Router address - Hardcoded for Mumbai
    // Check to get the router address for your supported network https://docs.chain.link/chainlink-functions/supported-networks
    address functionRouter = 0x6E2dc0F9DB014aE19888F539E59285D2Ea04244C;

    // JavaScript source code
    // Generate Random number that is kept private from the blockchain by using Secrets in Chainlink Functions
    // Encryptor must be smaller than RandomSeed number returned from VRF --> 78 digits so >25 digits should be adequate
    string source;
    uint32 functionGasLimit = 300000; //for Chainlink Functions

    // donID - Hardcoded for Mumbai
    // Check to get the donID for your supported network https://docs.chain.link/chainlink-functions/supported-networks
    bytes32 donID =
        0x66756e2d706f6c79676f6e2d6d756d6261692d31000000000000000000000000;

    uint64 SUBSCRIPTION_ID_FUNCTIONS; //subscriptionId for chainlink Function

    /////////////////////////////Game Variables///////////////////////////////////
    enum GameState {
        OPEN,
        IN_PROGRESS,
        AWAITING_RESPONSE,
        ENDED
    }

    struct ProphetData {
        address playerAddress;
        bool isAlive;
        bool isFree;
        uint256 args;
    }

    //Set interval to 3 minutes = 180
    uint256 INTERVAL;
    uint256 ENTRANCE_FEE;
    uint16 public NUMBER_OF_PROPHETS;
    address GAME_TOKEN;
    uint256 GAME_NUMBER;
    address OWNER;

    //Tracks tokens deposited each game, resets every game
    uint256 tokenBalance;
    uint256 lastRoundTimestamp;
    //mapping of addresses that have signed up to play by game: prophetList[GAME_NUMBER][address]
    //returns 0 if not signed up and 1 if has signed up
    mapping(uint256 => mapping(address => bool)) public prophetList;
    ProphetData[] public prophets;
    GameState public gameStatus;
    uint256 public prophetsRemaining;
    uint256 roleVRFSeed;
    uint256 gameRound;
    uint256 public currentProphetTurn;

    // mapping of which prophet each address holds allegiance tickets to
    mapping(uint256 => mapping(address => uint256)) public allegiance;
    // mapping of how many tickets an address owns
    mapping(uint256 => mapping(address => uint256)) public ticketsToValhalla;
    //tracks how many tickets to heaven have been sold for each Prophet
    uint256[] public accolites;
    uint256 public totalTickets;

    constructor(
        uint256 _interval,
        uint256 _entranceFee, //100000000000000
        uint16 _numProphets,
        address _gameToken, //0x326C977E6efc84E512bB9C30f76E30c160eD06FB Polygon Mumbia $LINK
        string memory _source,
        uint64 _functionSubscriptionId //Chainlink Functions Subscription ID 1053
    ) FunctionsClient(functionRouter) ConfirmedOwner(msg.sender) {
        OWNER = msg.sender;
        INTERVAL = _interval;
        ENTRANCE_FEE = _entranceFee;
        NUMBER_OF_PROPHETS = _numProphets;
        GAME_NUMBER = 0;
        gameStatus = GameState.OPEN;
        lastRoundTimestamp = block.timestamp;
        gameRound = 0;

        GAME_TOKEN = _gameToken;
        tokenBalance = 0;

        source = _source;
        SUBSCRIPTION_ID_FUNCTIONS = _functionSubscriptionId;
    }

    function setSource(string memory _source) public onlyOwner {
        source = _source;
    }

    function enterGame() public {
        if (gameStatus != GameState.OPEN) {
            revert Game__NotOpen();
        }
        if (prophets.length >= NUMBER_OF_PROPHETS) {
            revert Game__Full();
        }
        //for (uint256 prophet = 0; prophet < prophets.length; prophet++) {
        if (prophetList[GAME_NUMBER][msg.sender]) {
            revert Game__AlreadyRegistered();
        }
        //}
        ProphetData memory newProphet;
        newProphet.playerAddress = msg.sender;
        newProphet.isAlive = true;
        newProphet.isFree = true;
        prophets.push(newProphet);
        tokenBalance += ENTRANCE_FEE;
        prophetList[GAME_NUMBER][msg.sender] = true;
        prophetsRemaining++;

        IERC20(GAME_TOKEN).transferFrom(
            msg.sender,
            address(this),
            ENTRANCE_FEE
        );
    }

    function startGame() public {
        if (gameStatus != GameState.OPEN) {
            revert Game__NotOpen();
        }
        if (prophets.length != NUMBER_OF_PROPHETS) {
            revert Game__NotEnoughProphets();
        }

        gameStatus = GameState.IN_PROGRESS;
        // Need to make sure our JavaScript code can handle the number so divide into a smaller number
        roleVRFSeed = (uint256(blockhash(block.number - 1))) % 9007199254740991;

        currentProphetTurn = block.timestamp % NUMBER_OF_PROPHETS;
        sendRequest(3);
    }

    function setStart() public {
        if (gameRound == 0) {
            for (
                uint _prophet = 0;
                _prophet < s_lastFunctionResponse.length;
                _prophet++
            ) {
                if (s_lastFunctionResponse[_prophet] == "1") {
                    // assign allegiance to self
                    allegiance[GAME_NUMBER][
                        prophets[_prophet].playerAddress
                    ] = _prophet;
                    // give Prophet one of his own tickets
                    ticketsToValhalla[GAME_NUMBER][
                        prophets[_prophet].playerAddress
                    ] = 1;
                    // Increment total tickets by 1
                    totalTickets++;
                    // This loop initializes accolites[]
                    // each loop pushes the number of accolites/tickets sold into the prophet slot of the array
                    accolites.push(1);
                } else {
                    accolites.push(0);
                    prophetsRemaining--;
                    prophets[_prophet].isAlive = false;
                    prophets[_prophet].args = 99;
                }
            }
            turnManager();
            gameStatus = GameState.IN_PROGRESS;
        }
    }

    function ruleCheck() internal view {
        // Game must be in progress
        if (gameStatus != GameState.IN_PROGRESS) {
            revert Game__NotInProgress();
        }
        // Sending address must be their turn
        if (msg.sender != prophets[currentProphetTurn].playerAddress) {
            revert Game__OutOfTurn();
        }
    }

    // game needs to be playing, prophet must be alive
    function attemptSmite(uint256 _target) public {
        ruleCheck();
        // Prophet to smite must be alive and exist
        if (
            prophets[_target].isAlive == false || _target >= NUMBER_OF_PROPHETS
        ) {
            revert Game__NotAllowed();
        }

        prophets[currentProphetTurn].args = _target;
        gameStatus = GameState.AWAITING_RESPONSE;
        sendRequest(1);
    }

    function performMiracle() public {
        ruleCheck();

        gameStatus = GameState.AWAITING_RESPONSE;
        sendRequest(0);
    }

    function accuseOfBlasphemy(uint256 _target) public {
        ruleCheck();
        // Prophet to accuse must be alive and exist
        if (
            prophets[_target].isAlive == false || _target >= NUMBER_OF_PROPHETS
        ) {
            revert Game__NotAllowed();
        }
        // Message Sender must be living & free prophet on their turn
        if (prophets[currentProphetTurn].isFree == false) {
            revert Game__ProphetNotFree();
        }
        prophets[currentProphetTurn].args = _target;
        gameStatus = GameState.AWAITING_RESPONSE;
        sendRequest(2);
    }

    function forceTurn() public {
        if (
            block.timestamp < lastRoundTimestamp + INTERVAL ||
            gameStatus != GameState.IN_PROGRESS
        ) {
            revert Game__NotAllowed();
        }
        gameStatus = GameState.AWAITING_RESPONSE;
        sendRequest(0);
    }

    function setArgs(uint256 _action) internal {
        delete args;
        args.push(Strings.toString(roleVRFSeed));
        args.push(Strings.toString(NUMBER_OF_PROPHETS));
        args.push(Strings.toString(_action));
        args.push(Strings.toString(currentProphetTurn));
        args.push(Strings.toString(getTicketShare(currentProphetTurn)));
    }

    // Allow NUMBER_OF_PROPHETS to be changed in Hackathon but maybe don't let this happen in Production?
    // There may be a griefing vector I haven't thought of
    function reset(uint16 _numberOfPlayers) public {
        if (msg.sender != OWNER) {
            if (gameStatus != GameState.ENDED) {
                revert Game__NotInProgress();
            }
            if (block.timestamp < lastRoundTimestamp + INTERVAL) {
                revert Game__NotAllowed();
            }
        }

        GAME_NUMBER++;
        tokenBalance = 0;
        delete prophets; //array of structs
        gameStatus = GameState.OPEN;
        prophetsRemaining = 0;
        gameRound = 0;
        currentProphetTurn = 0;
        NUMBER_OF_PROPHETS = _numberOfPlayers;

        delete accolites; //array
        totalTickets = 0;
    }

    ///////////////////////////////////////////////////////////////////////////////////
    //////////////////       Functions to execute OffChain          ///////////////////
    ///////////////////////////////////////////////////////////////////////////////////

    function sendRequest(uint256 action) internal returns (bytes32 requestId) {
        //Need to figure out how to send encrypted secret!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        gameStatus = GameState.AWAITING_RESPONSE;
        setArgs(action);

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source); // Initialize the request with JS code
        if (encryptedSecretsUrls.length > 0)
            req.addSecretsReference(encryptedSecretsUrls);
        else if (donHostedSecretsVersion > 0) {
            req.addDONHostedSecrets(
                donHostedSecretsSlotID,
                donHostedSecretsVersion
            );
        }

        req.setArgs(args); // Set the arguments for the request

        // Send the request and store the request ID
        s_lastFunctionRequestId = _sendRequest(
            req.encodeCBOR(),
            SUBSCRIPTION_ID_FUNCTIONS,
            functionGasLimit,
            donID
        );
        return s_lastFunctionRequestId;
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (s_lastFunctionRequestId != requestId) {
            revert UnexpectedRequestID(requestId);
        }
        s_lastFunctionResponse = response;
        s_lastFunctionError = err;

        //logic to change state of contract
        if (response.length == 1) {
            uint256 target = prophets[currentProphetTurn].args;
            //logic for unsuccessful miracle
            if (response[0] == "0") {
                // kill prophet
                prophets[currentProphetTurn].isAlive = false;
                // Remove Prophet's accolite tickets from totalTickets for TicketShare calc
                totalTickets -= accolites[currentProphetTurn];
                // decrease number of remaining prophets
                prophetsRemaining--;
            }
            // Logic for successful miracle
            else if (response[0] == "1") {
                // if in jail, release from jail
                if (prophets[currentProphetTurn].isFree == false) {
                    prophets[currentProphetTurn].isFree = true;
                }
            }
            // Logic for an unsuccessful smite
            else if (response[0] == "2") {}
            // Logic for a successful smite
            else if (response[0] == "3") {
                prophets[target].isAlive = false;
                // Remove Dead Prophet's accolite tickets from totalTickets for TicketShare calc
                totalTickets -= accolites[target];
                prophetsRemaining--;
            }
            // Logic for unsuccessful accusation
            else if (response[0] == "4") {
                prophets[target].isFree = true;
            }
            // Logic for successful accusation
            else if (response[0] == "5") {
                if (prophets[target].isFree == true) {
                    prophets[target].isFree = false;
                } else {
                    prophets[target].isAlive = false;
                    // Remove Dead Prophet's accolite tickets from totalTickets for TicketShare calc
                    totalTickets -= accolites[target];
                    prophetsRemaining--;
                }
            }
            turnManager();
            gameStatus = GameState.IN_PROGRESS;
        }
        // Only time more than one response is returned is at start game
        // This is the start game logic
        /*else if (response.length > 1) {
            for (uint _prophet = 0; _prophet < response.length; _prophet++) {
                if (response[_prophet] == "1") {
                    // assign allegiance to self
                    allegiance[GAME_NUMBER][
                        prophets[_prophet].playerAddress
                    ] = _prophet;
                    // give Prophet one of his own tickets
                    ticketsToValhalla[GAME_NUMBER][
                        prophets[_prophet].playerAddress
                    ] = 1;
                    // Increment total tickets by 1
                    totalTickets++;
                    // This loop initializes accolites[]
                    // each loop pushes the number of accolites/tickets sold into the prophet slot of the array
                    accolites.push(1);
                } else {
                    accolites.push(0);
                    prophetsRemaining--;
                    prophets[_prophet].isAlive = false;
                    prophets[_prophet].args = 99;
                }
            }
        }*/
    }

    function turnManager() internal {
        if (prophetsRemaining == 1) {
            gameStatus = GameState.ENDED;
            tokenBalance = (tokenBalance * 95) / 100;
        }
        bool stillFinding = true;
        uint256 nextProphetTurn = currentProphetTurn + 1;
        while (stillFinding) {
            if (nextProphetTurn >= NUMBER_OF_PROPHETS) {
                nextProphetTurn = 0;
            }
            if (prophets[nextProphetTurn].isAlive) {
                currentProphetTurn = nextProphetTurn;
                gameRound++;
                lastRoundTimestamp = block.timestamp;
                stillFinding = false;
            }
            nextProphetTurn++;
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////////
    //////////// TICKET FUNCTIONS //////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////
    function getTicketShare(uint256 _playerNum) public view returns (uint256) {
        if (totalTickets == 0) return 0;
        else return (accolites[_playerNum] * 100) / totalTickets;
    }

    function highPriest(uint256 _senderProphetNum, uint256 _target) public {
        // Only prophets can call this function
        // Prophet must be alive or assigned to high priest
        // Can't try to follow non-existent prophet
        if (
            prophets[_senderProphetNum].playerAddress != msg.sender ||
            (!prophets[_senderProphetNum].isAlive &&
                prophets[_senderProphetNum].args != 99) ||
            _target >= NUMBER_OF_PROPHETS
        ) {
            revert Game__NotAllowed();
        }
        // Can't change allegiance if following an eliminated prophet
        if (prophets[allegiance[GAME_NUMBER][msg.sender]].isAlive == false) {
            revert Game__AddressIsEliminated();
        }
        if (gameStatus != GameState.IN_PROGRESS) {
            revert Game__NotInProgress();
        }
        if (ticketsToValhalla[GAME_NUMBER][msg.sender] > 0) {
            accolites[allegiance[GAME_NUMBER][msg.sender]]--;
            ticketsToValhalla[GAME_NUMBER][msg.sender]--;
            allegiance[GAME_NUMBER][msg.sender] = 0;
            totalTickets--;
        }
        accolites[_target]++;
        ticketsToValhalla[GAME_NUMBER][msg.sender]++;
        allegiance[GAME_NUMBER][msg.sender] = _target;
        totalTickets++;
    }

    function getPrice(
        uint256 supply,
        uint256 amount
    ) public pure returns (uint256) {
        uint256 sum1 = supply == 0
            ? 0
            : ((supply - 1) * (supply) * (2 * (supply - 1) + 1)) / 6;
        uint256 sum2 = supply == 0 && amount == 1
            ? 1
            : ((supply + amount - 1) *
                (supply + amount) *
                (2 * (supply + amount - 1) + 1)) / 6;
        uint256 summation = sum2 - sum1;
        return (summation * 1 ether) / 80;
    }

    function getReligion(uint256 _prophetNum, uint256 _ticketsToBuy) public {
        // Make sure game state allows for tickets to be bought
        if (gameStatus != GameState.IN_PROGRESS) {
            revert Game__NotInProgress();
        }
        // Prophets cannot buy tickets
        if (prophetList[GAME_NUMBER][msg.sender]) {
            revert Game__NotAllowed();
        }
        // Can't buy tickets of dead or nonexistent prophets
        if (
            prophets[_prophetNum].isAlive == false ||
            _prophetNum >= NUMBER_OF_PROPHETS
        ) {
            revert Game__ProphetIsDead();
        }
        // Cannot buy/sell  tickets if address eliminated (allegiant to prophet when killed)
        // Addresses that own no tickets will default allegiance to 0 but 0 is a player number
        //  This causes issues with game logic so if allegiance is to 0
        //  we must also check if sending address owns tickets
        // If the address owns tickets then they truly have allegiance to player 0
        if (
            prophets[allegiance[GAME_NUMBER][msg.sender]].isAlive == false &&
            ticketsToValhalla[GAME_NUMBER][msg.sender] != 0
        ) {
            revert Game__AddressIsEliminated();
        }

        // Check if player owns any tickets of another prophet
        if (
            ticketsToValhalla[GAME_NUMBER][msg.sender] != 0 &&
            allegiance[GAME_NUMBER][msg.sender] != _prophetNum
        ) {
            revert Game__NotAllowed();
        }

        uint256 totalPrice = getPrice(
            accolites[allegiance[GAME_NUMBER][msg.sender]],
            _ticketsToBuy
        );

        ticketsToValhalla[GAME_NUMBER][msg.sender] += _ticketsToBuy;
        accolites[_prophetNum] += _ticketsToBuy;
        totalTickets += _ticketsToBuy;
        tokenBalance += totalPrice;
        allegiance[GAME_NUMBER][msg.sender] = _prophetNum;
        //emit TicketsBought(_buyerAddress, ticketsBought, totalPrice);

        IERC20(GAME_TOKEN).transferFrom(msg.sender, address(this), totalPrice);
    }

    function loseReligion(uint256 _ticketsToSell) public {
        if (gameStatus != GameState.IN_PROGRESS) {
            revert Game__NotInProgress();
        }
        // Can't sell tickets of a dead prophet
        if (prophets[allegiance[GAME_NUMBER][msg.sender]].isAlive == false) {
            revert Game__ProphetIsDead();
        }
        // Prophets cannot sell tickets
        if (prophetList[GAME_NUMBER][msg.sender]) {
            revert Game__NotAllowed();
        }
        if (_ticketsToSell <= ticketsToValhalla[GAME_NUMBER][msg.sender]) {
            // Get price of selling tickets
            uint256 totalPrice = getPrice(
                accolites[allegiance[GAME_NUMBER][msg.sender]] - _ticketsToSell,
                _ticketsToSell
            );
            // Reduce the total number of tickets sold in the game by number of tickets sold by msg.sender
            totalTickets -= _ticketsToSell;
            // Remove tickets from msg.sender's balance
            ticketsToValhalla[GAME_NUMBER][msg.sender] -= _ticketsToSell;
            // If msg.sender sold all tickets then set allegiance to 0
            if (ticketsToValhalla[GAME_NUMBER][msg.sender] == 0)
                allegiance[GAME_NUMBER][msg.sender] = 0;
            // Subtract the price of tickets sold from the tokenBalance for this game
            tokenBalance -= totalPrice;
            //Take 5% fee
            totalPrice = (totalPrice * 95) / 100;
            //emit TicketsSold(_sellerAddress, ticketsSold, totalPrice);

            IERC20(GAME_TOKEN).transfer(msg.sender, totalPrice);
        } else revert Game__NotEnoughTicketsOwned();
    }

    function claimTickets() public {
        if (gameStatus != GameState.ENDED) {
            revert Game__NotAllowed();
        }
        // TurnManager sets currentProphetTurn to game winner, so use this to check if allegiance is to the winner
        if (allegiance[GAME_NUMBER][msg.sender] != currentProphetTurn) {
            revert Game__AddressIsEliminated();
        }
        if (ticketsToValhalla[GAME_NUMBER][msg.sender] == 0) {
            revert Game__NotEnoughTicketsOwned();
        }
        //This is prone to rounding error?
        uint256 tokensPerTicket = tokenBalance / accolites[currentProphetTurn];
        uint256 tokensToSend = ticketsToValhalla[GAME_NUMBER][msg.sender] *
            tokensPerTicket;
        ticketsToValhalla[GAME_NUMBER][msg.sender] = 0;

        IERC20(GAME_TOKEN).transfer(msg.sender, tokensToSend);
    }

    function ownerTokenTransfer(
        uint256 _amount,
        address _token,
        address _destination
    ) public onlyOwner {
        IERC20(_token).transfer(_destination, _amount);
    }
}
