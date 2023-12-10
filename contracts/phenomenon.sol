// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

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

contract Phenomenon is FunctionsClient, VRFConsumerBaseV2, ConfirmedOwner {
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

    uint256[] public requestIdsVRF; //for random number
    uint256 public lastRequestIdVRF; //for random number

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
    uint32 callbackGasLimitVRF = 1000000; //for VRF random number

    uint16 requestConfirmations = 3; //for VRF random number
    uint32 numWords = 1; //for VRF random number

    // donID - Hardcoded for Mumbai
    // Check to get the donID for your supported network https://docs.chain.link/chainlink-functions/supported-networks
    bytes32 donID =
        0x66756e2d706f6c79676f6e2d6d756d6261692d31000000000000000000000000;

    //struct for VRF random number
    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256[] randomWords;
    }

    //mapping of uint256 to random word/number return value
    mapping(uint256 => RequestStatus) public s_requestsVRF;
    VRFCoordinatorV2Interface COORDINATOR;

    uint64 s_subscriptionIdVRF; //subscriptionId for chainlink VRF random Number
    uint64 SUBSCRIPTION_ID_FUNCTIONS; //subscriptionId for chainlink Function
    bytes latestVRFResponse;
    bytes latestVRFError;

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
    uint256 public GAME_NUMBER;
    address OWNER;

    //Tracks tokens deposited each game, resets every game
    uint256 tokenBalance;
    uint256 lastRoundTimestamp;
    //mapping of addresses that have signed up to play by game: prophetList[GAME_NUMBER][address]
    //returns 0 if not signed up and 1 if has signed up
    mapping(uint256 => mapping(address => uint256)) public prophetList;
    ProphetData[] public prophets;
    GameState public gameStatus;
    uint256 public prophetsRemaining;
    uint256 public roleVRFSeed;
    uint256 public gameRound;
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
        uint64 _subscriptionId, //Chainlink VRF SubscriptionID 6616
        uint64 _functionSubscriptionId //Chainlink Functions Subscription ID 1053
    )
        FunctionsClient(functionRouter)
        VRFConsumerBaseV2(0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed)
        ConfirmedOwner(msg.sender)
    {
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
        COORDINATOR = VRFCoordinatorV2Interface(
            0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed
        );
        s_subscriptionIdVRF = _subscriptionId;
        SUBSCRIPTION_ID_FUNCTIONS = _functionSubscriptionId;
    }

    function setSource(string memory _source) public {
        if (msg.sender != OWNER) {
            revert Contract__OnlyOwner();
        }
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
        if (prophetList[GAME_NUMBER][msg.sender] == 1) {
            revert Game__AlreadyRegistered();
        }
        //}
        ProphetData memory newProphet;
        newProphet.playerAddress = msg.sender;
        newProphet.isAlive = true;
        newProphet.isFree = true;
        prophets.push(newProphet);
        tokenBalance += ENTRANCE_FEE;
        prophetList[GAME_NUMBER][msg.sender] = 1;
        prophetsRemaining++;
        if (prophetsRemaining == 1) {
            requestRandomWords();
        }

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

        if (s_requestsVRF[lastRequestIdVRF].exists == false) {
            revert Game__NoRandomNumber();
        }
        gameStatus = GameState.IN_PROGRESS;
        // Need to make sure our JavaScript code can handle the number so divide into a smaller number
        roleVRFSeed =
            s_requestsVRF[lastRequestIdVRF].randomWords[0] %
            9007199254740991;

        currentProphetTurn = block.timestamp % NUMBER_OF_PROPHETS;
        sendRequest(3);
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

    // Allow NUMBER_OF_PROPHETS to be changed in Hackathon but maybe don't let this happen in Production
    // There may be a griefing vector I haven't thought of
    function reset(uint16 _numberOfPlayers) public {
        if (gameStatus != GameState.ENDED) {
            revert Game__NotInProgress();
        }
        if (block.timestamp < lastRoundTimestamp + INTERVAL) {
            revert Game__NotAllowed();
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

    function setStart() public {
        if (gameRound == 1) {
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
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////
    //////////////////       Functions to execute OffChain          ///////////////////
    ///////////////////////////////////////////////////////////////////////////////////
    function requestRandomWords() internal returns (uint256 requestId) {
        // Will revert if subscription is not set and funded.
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionIdVRF,
            requestConfirmations,
            callbackGasLimitVRF,
            numWords
        );
        s_requestsVRF[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });
        requestIdsVRF.push(requestId);
        lastRequestIdVRF = requestId;
        //emit RequestSent(requestId, numWords);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requestsVRF[_requestId].exists, "request not found");
        s_requestsVRF[_requestId].fulfilled = true;
        s_requestsVRF[_requestId].randomWords = _randomWords;
        //emit RequestFulfilled(_requestId, _randomWords);
    }

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
                    prophetsRemaining--;
                }
            }
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
        gameStatus = GameState.IN_PROGRESS;
        turnManager();
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

    function getTicketShare(uint256 _playerNum) public view returns (uint256) {
        if (totalTickets == 0) return 0;
        else return (accolites[_playerNum] * 100) / totalTickets;
    }

    ////////////////////////////////////////////////////////////////////////////////////////////
    //////////// TICKET FUNCTIONS //////////////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////

    function highPriest(uint256 _prophetNum, uint256 _target) public {
        if (
            msg.sender != prophets[_prophetNum].playerAddress &&
            prophets[_prophetNum].args != 99
        ) {
            revert Game__NotAllowed();
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

    /*
    function getReligion(uint256 _prophetNum, uint256 _ticketsToBuy) public {
        // Make sure game state allows for tickets to be bought
        if (gameStatus != GameState.IN_PROGRESS) {
            revert Game__NotInProgress();
        }
        // Prophets cannot buy tickets
        if (prophetList[GAME_NUMBER][msg.sender] == 1) {
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

        // Check if player owns any tickets, if yes -> sell all tickets and buy
        if (
            ticketsToValhalla[GAME_NUMBER][msg.sender] != 0 &&
            allegiance[GAME_NUMBER][msg.sender] != _prophetNum
        ) {
            //sell tickets of prior religion, function will assign allegiance to 0
            sellTickets(
                allegiance[GAME_NUMBER][msg.sender],
                ticketsToValhalla[GAME_NUMBER][msg.sender],
                msg.sender
            );
        }

        buyTicketsToValhalla(_prophetNum, _ticketsToBuy, msg.sender);
        allegiance[GAME_NUMBER][msg.sender] = _prophetNum;
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
        if (prophetList[GAME_NUMBER][msg.sender] == 1) {
            revert Game__NotAllowed();
        }
        if (_ticketsToSell <= ticketsToValhalla[GAME_NUMBER][msg.sender]) {
            sellTickets(
                allegiance[GAME_NUMBER][msg.sender],
                _ticketsToSell,
                msg.sender
            );
        } else revert Game__NotEnoughTicketsOwned();
    }

    function buyTicketsToValhalla(
        uint256 _prophetNum,
        uint256 _amountToBuy,
        address _buyerAddress
    ) internal {
        // check how many tickets exist for _playerNum
        uint256 totalPrice = 0;
        uint256 ticketsBought = 0;
        while (ticketsBought < _amountToBuy) {
            ticketsBought++;
            totalPrice +=
                (((accolites[_prophetNum] + ticketsBought) *
                    (accolites[_prophetNum] + ticketsBought)) *
                    1000000000000000000) /
                8000;
        }

        ticketsToValhalla[GAME_NUMBER][_buyerAddress] += ticketsBought;
        accolites[_prophetNum] += ticketsBought;
        totalTickets += ticketsBought;
        tokenBalance += totalPrice;
        //emit TicketsBought(_buyerAddress, ticketsBought, totalPrice);

        IERC20(GAME_TOKEN).transferFrom(
            _buyerAddress,
            address(this),
            totalPrice
        );
    }

    function sellTickets(
        uint256 _prophetNum,
        uint256 _amountToSell,
        address _sellerAddress
    ) internal {
        uint256 totalPrice = 0;
        uint256 ticketsSold = 0;
        while (ticketsSold < _amountToSell) {
            totalPrice += ((((accolites[_prophetNum]) *
                (accolites[_prophetNum])) * 1000000000000000000) / 8000);
            ticketsSold++;
            accolites[_prophetNum]--;
        }

        totalTickets -= ticketsSold;
        ticketsToValhalla[GAME_NUMBER][_sellerAddress] -= ticketsSold;
        if (ticketsToValhalla[GAME_NUMBER][_sellerAddress] == 0)
            allegiance[GAME_NUMBER][_sellerAddress] = 0;
        tokenBalance -= totalPrice;
        //Take 5% fee
        totalPrice = (totalPrice * 95)/100;
        //emit TicketsSold(_sellerAddress, ticketsSold, totalPrice);

        IERC20(GAME_TOKEN).transfer(_sellerAddress, totalPrice);
    } */

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
    ) public {
        if (msg.sender != OWNER) {
            revert Contract__OnlyOwner();
        }
        IERC20(_token).transfer(_destination, _amount);
    }
}
