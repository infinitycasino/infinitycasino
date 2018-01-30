pragma solidity ^0.4.18;

import "./usingOraclize.sol";
import "./InfinityBankroll.sol";

contract InfinityDice is InfinityCasinoGameInterface, usingOraclize {

	// events
	event BuyRolls(bytes32 indexed oraclizeQueryId);
	event LedgerProofFailed(bytes32 indexed oraclizeQueryId);
	event Refund(bytes32 indexed oraclizeQueryId, uint256 amount);
	// each roll will be logged as 0 -> loss, 1 -> win
	event DiceSmallBet(uint16 actualRolls, uint256 data1, uint256 data2, uint256 data3, uint256 data4);
	event DiceLargeBet(bytes32 indexed oraclizeQueryId, uint16 actualRolls, uint256 data1, uint256 data2, uint256 data3, uint256 data4);

	// game data structure
	struct DiceGameData {
		address player;
		bool paidOut;
		uint256 start;
		uint256 etherReceived;
		uint256 betPerRoll;
		uint16 rolls;
		uint8 rollUnder;
	}

	mapping (bytes32 => DiceGameData) public diceData;

	uint256 public BANKROLL;
	uint256 public LIABILITIES;
	uint256 public AMOUNTWAGERED;
	uint256 public AMOUNTPAIDOUT;
	uint256 public GAMESPLAYED;
	uint256 public DEVELOPERSFUND;

	uint256 public ORACLIZEQUERYMAXTIME;
	//  // if betPerRoll is over this amount, oraclize query will trigger so that miners cannot cheat
	//  // if betPerRoll is under this amount, bet will be resolved immedately using blockhash. Miners will not cheat because 
	//  // of the economic disincentive (see python simulation on our github)
	uint256 public MINBET_forORACLIZE;
	uint256 public MINBET;
	uint256 public ORACLIZEGASPRICE;
	uint8 public HOUSEEDGE_inTHOUSANDTHPERCENTS; // 1 thousanthpercent == 1/1000, 
	uint8 public MAXWIN_inTHOUSANDTHPERCENTS; // determines the maximum win a user may receive.

	bool public GAMEPAUSED;

	address public OWNER;

	address public BANKROLLER;
	InfinityBankroll public BANKROLLERINSTANCE;

	function InfinityDice() public {
		// ledger proof is ALWAYS verified on-chain

		//////////////////////////////////////////////////////////////////
		// WARNING---THIS MUST BE ENABLED ON LIVE DEPLOYMENT!!!!!!!!!!
		//////////////////////////////////////////////////////////////////
		// oraclize_setProof(proofType_Ledger);

		// initially set gas price to 10 Gwei, but this can be changed later to account for network congestion.
		oraclize_setCustomGasPrice(10000000000);
		ORACLIZEGASPRICE = 10000000000;

		//////////////////////////////////////////////////////////////////
		// WARNING---THIS MUST BE REMOVED ON DEPLOYMENT!!!!!!!!
		//////////////////////////////////////////////////////////////////
		OAR = OraclizeAddrResolverI(0x6f485c8bf6fc43ea212e93bbf8ce046c7f1cb475);

		AMOUNTWAGERED = 0;
		AMOUNTPAIDOUT = 0;
		GAMESPLAYED = 0;
		GAMEPAUSED = false;

		ORACLIZEQUERYMAXTIME = 6 hours;
		MINBET_forORACLIZE = 1250 finney; // 1250 finney or 1.25 ether is a limit to prevent an incentive for miners to cheat, any more will be forwarded to oraclize!
		MINBET = 10 finney;
		HOUSEEDGE_inTHOUSANDTHPERCENTS = 10; // 10/1000 == 1% house edge
		MAXWIN_inTHOUSANDTHPERCENTS = 20; // 20/1000 == 2% of bankroll 
		OWNER = msg.sender;
	}

	function acceptEtherFromBankrollContract() payable public {
		require(msg.sender == BANKROLLER);

		BANKROLL += msg.value;
	} 

	function payEtherToBankrollContract(uint256 amountToSend) public {
		require(msg.sender == BANKROLLER && amountToSend <= BANKROLL);

		// decrement bankroll by amount to send, and send the amount to the bankroll contract.
		BANKROLL -= amountToSend;
		BANKROLLERINSTANCE.receiveEtherFromGameAddress.value(amountToSend)();
	}

	function payDevelopersFund(address developer) public {
		require(msg.sender == BANKROLLER);

		uint256 devFund = DEVELOPERSFUND;

		DEVELOPERSFUND = 0;

		developer.transfer(devFund);
	}

	// owner only, management functions below...

	// WARNING!!!!! Can only set this function once!
	function setBankrollerContractOnce(address bankrollAddress) public {
		// require that BANKROLLER address == 0 (address not set yet), and coming from owner.
		require(msg.sender == OWNER && BANKROLLER == address(0));

		BANKROLLER = bankrollAddress;
		BANKROLLERINSTANCE = InfinityBankroll(bankrollAddress);
	}

	function transferOwnership(address newOwner) public {
		require(msg.sender == OWNER);

		OWNER = newOwner;
	}

	function setOraclizeQueryMaxTime(uint256 newTime) public {
		require(msg.sender == OWNER);

		ORACLIZEQUERYMAXTIME = newTime;
	}

	// store the gas price as a storage variable for easy reference,
	// and thne change the gas price using the proper oraclize function
	function setOraclizeQueryGasPrice(uint256 gasPrice) public {
		require(msg.sender == OWNER);

		ORACLIZEGASPRICE = gasPrice;
		oraclize_setCustomGasPrice(gasPrice);
	}

	function setGamePaused(bool paused) public {
		require(msg.sender == OWNER);

		GAMEPAUSED = paused;
	}

	function setHouseEdge(uint8 houseEdgeInThousandthPercents) public {
		// house edge cannot be set > 5%
		require(msg.sender == OWNER && houseEdgeInThousandthPercents <= 50);

		HOUSEEDGE_inTHOUSANDTHPERCENTS = houseEdgeInThousandthPercents;
	}

	function setMinBetForOraclize(uint256 minBet) public {
		require(msg.sender == OWNER);

		MINBET_forORACLIZE = minBet;
	}

	function setMinBet(uint256 minBet) public {
		require(msg.sender == OWNER);

		MINBET = minBet;
	}

	function setMaxWin(uint8 newMaxWinInThousandthPercents) public {
		// cannot set bet limit greater than 5% of total BANKROLL.
		require(msg.sender == OWNER && newMaxWinInThousandthPercents <= 50);

		MAXWIN_inTHOUSANDTHPERCENTS = newMaxWinInThousandthPercents;
	}

	// Can be removed after some testing...
	function emergencySelfDestruct() public {
		require(msg.sender == OWNER);

		selfdestruct(msg.sender);
	}

	// require that the query time is too slow, bet has not been paid out, and either contract owner or player is calling this function.
	// this will only be used/can occur on queries that are forwarded to oraclize in the first place. All others will be paid out immediately.
	function refund(bytes32 oraclizeQueryId) public {
		// store data in memory for easy access.
		DiceGameData memory data = diceData[oraclizeQueryId];

		require(block.timestamp - data.start >= ORACLIZEQUERYMAXTIME
			&& (msg.sender == OWNER || msg.sender == data.player)
			&& (!data.paidOut)
			&& LIABILITIES >= data.etherReceived);

		// set paidout == true, so users can't request more refunds, and a super delayed oraclize __callback will just get reverted
		diceData[oraclizeQueryId].paidOut = true;

		LIABILITIES -= data.etherReceived;
		AMOUNTWAGERED -= data.etherReceived;
		// then transfer the original bet to the player.
		data.player.transfer(data.etherReceived);
		// finally, log an event saying that the refund has processed.
		Refund(oraclizeQueryId, data.etherReceived);
	}

	function play(uint256 betPerRoll, uint16 rolls, uint8 rollUnder) public payable {

		require(!GAMEPAUSED
				&& msg.value > 0
				&& betPerRoll >= MINBET
				&& rolls > 0
				&& rolls <= 1024
				&& betPerRoll <= msg.value
				&& rollUnder > 1
				&& rollUnder < 100
				// make sure that the player cannot win more than the max win (forget about house edge here)
				&& (betPerRoll * 100) / (rollUnder - 1) <= (BANKROLL * MAXWIN_inTHOUSANDTHPERCENTS) / 1000);

		// if bets are relatively small, resolve the bet in-house
		if (betPerRoll < MINBET_forORACLIZE) {

			// again, randomness will be determined by keccak256(blockhash, nonce)
			// store these in memory for cheap access.
			bytes32 blockHash = block.blockhash(block.number);
			uint256 gamesPlayed = GAMESPLAYED;
			uint8 houseEdgeInThousandthPercents = HOUSEEDGE_inTHOUSANDTHPERCENTS;

			// these are variables that will be modified when the game runs
			// keep track of the amount to payout to the player
			// this will actually start as the received amount of ether, and will be incremented
			// or decremented based on whether each roll is winning or losing.
			// when payout gets below the etherReceived/rolls amount, then the loop will terminate.
			uint256 etherAvailable = msg.value;

			// these are the logs for the frontend...
			uint256[] memory data = new uint256[](4);

			uint16 i = 0;
			while (i < rolls && etherAvailable >= betPerRoll){
				// add 1 to gamesPlayed, this is the nonce.
				gamesPlayed++;
				// this roll is keccak256(blockhash, nonce) + 1 so between 1-100 (inclusive)

				if (uint8(uint256(keccak256(blockHash, gamesPlayed)) % 100) + 1 < rollUnder){
					// winner!
					// add the winnings to ether avail -> (betPerRoll * probability of hitting this number) * (house edge modifier)
					etherAvailable += (((betPerRoll * 100) / (rollUnder - 1) * (1000 - houseEdgeInThousandthPercents)) / 1000) - betPerRoll;
					// now assemble logs for the front end...
					if (i <= 255){
						// place a 1 in the i'th bit of data1
						data[0] += uint256(2) ** (255 - i);
					}
					else if (i <= 511){
						// place a 1 in the (i-256)'th bit of data2
						data[1] += uint256(2) ** (511 - i);
					}
					else if (i <= 767){
						data[2] += uint256(2) ** (767 - i);
					}
					else {
						// where i <= 1023
						data[3] += uint256(2) ** (1023 - i);
					}
				}
				else {
					// loser.
					// subtract betPerRoll, but leave 1 wei as a consolation prize :)
					etherAvailable -= (betPerRoll - 1);
					// we don't need to "place a zero" on this roll's spot in the binary strings, because they are init'ed to zero.
				}

				i++;
			}

			// every roll, we will transfer 10% of the profit to the developers fund (profit per roll = house edge)
			// that is: betPerRoll * (1%) * num rolls * (20%)
			uint256 developersCut = betPerRoll * houseEdgeInThousandthPercents * i / 5000;
			// add to DEVELOPERSFUND
			DEVELOPERSFUND += developersCut;

			// update the bankroll with whatever happened...
			BANKROLL -= (etherAvailable + developersCut - msg.value);
			// update amount wagered with betPerRoll * i (the amount of times the roll loop was executed)
			AMOUNTWAGERED += betPerRoll * i;
			// update amountpaidout with ether available minus original bet.
			AMOUNTPAIDOUT += etherAvailable;
			// update the gamesPlayer with how many games were played 
			GAMESPLAYED = gamesPlayed;
			// finally transfer the ether to the player (no reentrancy issues here...)
			msg.sender.transfer(etherAvailable);
			// log an event, with the outcome of the dice game, so that the frontend can parse it for the player.
			DiceSmallBet(i, data[0], data[1], data[2], data[3]);
		}

		// // otherwise, we need to save the game data into storage, and call oraclize
		// // to get the miner-interference-proof randomness for us.
		// // when oraclize calls back, we will reinstantiate the game data and resolve 
		// // the spins with the random number given by oraclize 
		else {

			bytes32 oraclizeQueryId;

			if (rolls <= 256){
				oraclizeQueryId = oraclize_newRandomDSQuery(0, 30, 375000);
				// add the amount bet to the bankroll minus gas spent on oraclize 
				BANKROLL -= 375000 * ORACLIZEGASPRICE;
			}
			else if (rolls <= 512){
				oraclizeQueryId = oraclize_newRandomDSQuery(0, 30, 575000);

				BANKROLL -= 575000 * ORACLIZEGASPRICE;
			}
			else if (rolls <= 768){
				oraclizeQueryId = oraclize_newRandomDSQuery(0, 30, 775000);

				BANKROLL -= 775000 * ORACLIZEGASPRICE;
			}
			else {
				oraclizeQueryId = oraclize_newRandomDSQuery(0, 30, 1000000);

				BANKROLL -= 1000000 * ORACLIZEGASPRICE;
			}

			diceData[oraclizeQueryId] = DiceGameData({
				player : msg.sender,
				paidOut : false,
				start : block.timestamp,
				etherReceived : msg.value,
				betPerRoll : betPerRoll,
				rolls : rolls,
				rollUnder : rollUnder
			});

			// log an event for the frontend
			LIABILITIES += msg.value;
			BuyRolls(oraclizeQueryId);
		}
	}

	// oraclize callback.
	// Basically do the instant bet resolution in the play(...) function above, but with the random data 
	// that oraclize returns, instead of getting psuedo-randomness from block.blockhash

	/////////////////////////////////////////////////////////////////////////////
	// WARNING---THIS NEED TO BE REENABLED UPON DEPLOYMENT!!!!!!!!!
	/////////////////////////////////////////////////////////////////////////////

	// function __callback(bytes32 _queryId, string _result, bytes _proof) public {
	function __callback(bytes32 _queryId, string _result) public {

		DiceGameData memory data = diceData[_queryId];
		// only need to check these, as all of the game based checks were already done in the play(...) function 
		require(msg.sender == oraclize_cbAddress() && !data.paidOut && data.player != address(0) && LIABILITIES >= data.etherReceived);

		// if the proof has failed, immediately refund the player his original bet...

		/////////////////////////////////////////////////////////////////////////////
		// WARNING---THIS NEEDS TO BE REENABLED UPON DEPLOYMENT!!!!!!!!!!!
		/////////////////////////////////////////////////////////////////////////////

		// if (oraclize_randomDS_proofVerify__returnCode(_queryId, _result, _proof) != 0){
		if (0 != 0){

			// set contract data
			diceData[_queryId].paidOut = true;

			LIABILITIES -= data.etherReceived;
			AMOUNTWAGERED -= data.etherReceived;
			// transfer the original bet
			data.player.transfer(data.etherReceived);
			// log these two events
			LedgerProofFailed(_queryId);
			Refund(_queryId, data.etherReceived);
		}
		// else, resolve the bet as normal with this miner-proof proven-randomness from oraclize.
		else {
			// save these in memory for cheap access
			uint256 gamesPlayed = GAMESPLAYED;
			uint8 houseEdgeInThousandthPercents = HOUSEEDGE_inTHOUSANDTHPERCENTS;

			// set the current balance available to the player as etherReceived
			uint256 etherAvailable = data.etherReceived;

			// logs for the frontend, as before...
			uint256[] memory logsData = new uint256[](4);

			// this loop is highly similar to the one from before. Instead of fully documented, the differences will be pointed out instead.
			uint16 i = 0;
			while (i < data.rolls && etherAvailable >= data.betPerRoll){
				
				gamesPlayed++;
				// now, this roll is keccak256(_result, nonce) + 1 ... this is the main difference from using oraclize.

				if (uint8(uint256(keccak256(_result, gamesPlayed)) % 100) + 1 < data.rollUnder){

					// now, just get the respective fields from data.field unlike before where they were in seperate variables.
					
					etherAvailable += (((data.betPerRoll * 100) / (data.rollUnder - 1) * (1000 - houseEdgeInThousandthPercents)) / 1000) - data.betPerRoll;
					// now assemble logs for the front end...
					if (i <= 255){
						// place a 1 in the i'th bit of data1
						logsData[0] += uint256(2) ** (255 - i);
					}
					else if (i <= 511){
						// place a 1 in the (i-256)'th bit of data2
						logsData[1] += uint256(2) ** (511 - i);
					}
					else if (i <= 767){
						logsData[2] += uint256(2) ** (767 - i);
					}
					else {
						// where i <= 1023
						logsData[3] += uint256(2) ** (1023 - i);
					}
				}
				else {
					// loser.
					// subtract betPerRoll, but leave 1 wei as a consolation prize :)
					etherAvailable -= (data.betPerRoll - 1);
				}
				i++;
			}

			// data.betPerRoll
			uint256 developersCut = data.betPerRoll * houseEdgeInThousandthPercents * i / 5000;

			DEVELOPERSFUND += developersCut;

			// etherReceived was already added to BANKROLL in the play(...) function, so just sub etherAvailable.
			BANKROLL += data.etherReceived - (etherAvailable + developersCut);
			LIABILITIES -= data.etherReceived;
			// now, get betPerRoll from data
			AMOUNTWAGERED += data.betPerRoll * i;

			AMOUNTPAIDOUT += etherAvailable;
			
			GAMESPLAYED = gamesPlayed;

			// IMPORTANT! since we have inited this gameData structure, we need to signal that we have finished using it to prevent reentrancy
			// set paidOut = true;
			diceData[_queryId].paidOut = true;

			// now get player from data, not msg.sender
			data.player.transfer(etherAvailable);

			// log an event, now with the oraclize query id
			DiceLargeBet(_queryId, i, logsData[0], logsData[1], logsData[2], logsData[3]);
		}
	}


// END OF CONTRACT. REPORT ANY BUGS TO DEVELOPMENT@INFINITYCASINO.IO
// YES! WE _DO_ HAVE A BUG BOUNTY PROGRAM!

// THANK YOU FOR READING THIS CONTRACT, HAVE A NICE DAY :)

}
