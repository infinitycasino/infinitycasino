pragma solidity ^0.4.18;

import "./usingOraclize.sol";
import "./InfinityBankroll.sol";
import "./SafeMath.sol";

contract MoonMissionSlots is InfinityCasinoGameInterface, usingOraclize {

	using SafeMath for *;

	// events
	event BuyCredits(bytes32 indexed oraclizeQueryId);
	event LedgerProofFailed(bytes32 indexed oraclizeQueryId);
	event Refund(bytes32 indexed oraclizeQueryId, uint256 amount);
	event SlotsLargeBet(bytes32 indexed oraclizeQueryId, uint256 data1, uint256 data2, uint256 data3, uint256 data4, uint256 data5, uint256 data6, uint256 data7, uint256 data8);
	event SlotsSmallBet(uint256 data1, uint256 data2, uint256 data3, uint256 data4, uint256 data5, uint256 data6, uint256 data7, uint256 data8);

	// slots game structure
	struct SlotsGameData {
		address player;
		bool paidOut;
		uint256 start;
		uint256 etherReceived;
		uint8 credits;
	}

	mapping (bytes32 => SlotsGameData) public slotsData;

	uint256 public BANKROLL;
	uint256 public LIABILITIES;
	uint256 public AMOUNTWAGERED;
	uint256 public AMOUNTPAIDOUT;
	uint256 public DIALSSPUN;
	uint256 public DEVELOPERSFUND;

	uint256 public ORACLIZEQUERYMAXTIME;
	uint256 public MINBET_forORACLIZE;
	uint256 public MINBET;
	uint256 public ORACLIZEGASPRICE;
	uint16 public MAXWIN_inTHOUSANDTHPERCENTS;

	bool public GAMEPAUSED;

	address public OWNER;

	address public BANKROLLER;
	InfinityBankroll public BANKROLLERINSTANCE;

	// constructor
	function MoonMissionSlots() public {

		// ledger proof is ALWAYS verified on-chain

		/////////////////////////////////////////////////////////////////////////////
		// WARNING---THIS MUST BE ENABLED ON LIVE DEPLOYMENT!!!!!!!!!!
		/////////////////////////////////////////////////////////////////////////////

		// oraclize_setProof(proofType_Ledger);

		oraclize_setCustomGasPrice(10000000000);
		ORACLIZEGASPRICE = 10000000000;

		/////////////////////////////////////////////////////////////////////////////
		// WARNING---THIS MUST BE REMOVED ON DEPLOYMENT!!!!!!!!
		/////////////////////////////////////////////////////////////////////////////
		OAR = OraclizeAddrResolverI(0x6f485c8bf6fc43ea212e93bbf8ce046c7f1cb475);

		AMOUNTWAGERED = 0;
		AMOUNTPAIDOUT = 0;
		DIALSSPUN = 0;
		GAMEPAUSED = false;

		ORACLIZEQUERYMAXTIME = 6 hours;
		MINBET_forORACLIZE = 1250 finney; // 1.25 ether is the max bet to avoid miner cheating. see python sim. on our github
		MINBET = 1 finney; // currently, this is ~40-50c a spin, which is pretty average slots. This is changeable by OWNER 
        MAXWIN_inTHOUSANDTHPERCENTS = 500; // 250/1000 so a jackpot can take 25% of bankroll (extremely rare)
        OWNER = msg.sender;
	}

	// bankroller contract address only functions below...

	function acceptEtherFromBankrollContract() payable public {
		require(msg.sender == BANKROLLER);

		BANKROLL = SafeMath.add(BANKROLL, msg.value);
	} 

	function payEtherToBankrollContract(uint256 amountToSend) public {
		require(msg.sender == BANKROLLER && amountToSend <= BANKROLL);

		// decrement bankroll by amount to send, and send the amount to the bankroll contract.
		BANKROLL = SafeMath.sub(BANKROLL, amountToSend);
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

	function setMinBetForOraclize(uint256 minBet) public {
		require(msg.sender == OWNER);

		MINBET_forORACLIZE = minBet;
	}

	function setMinBet(uint256 minBet) public {
		require(msg.sender == OWNER);

		MINBET = minBet;
	}

	function setMaxwin(uint16 newMaxWinInThousandthPercents) public {
		require(msg.sender == OWNER && newMaxWinInThousandthPercents <= 333); // cannot set max win greater than 1/3 of the bankroll (a jackpot is very rare)

		MAXWIN_inTHOUSANDTHPERCENTS = newMaxWinInThousandthPercents;
	}

	// this can be deleted after some testing.
	function emergencySelfDestruct() public {
		require(msg.sender == OWNER);

		selfdestruct(msg.sender);
	}

	function refund(bytes32 oraclizeQueryId) public {
		// save into memory for cheap access
		SlotsGameData memory data = slotsData[oraclizeQueryId];

		//require that the query time is too slow, bet has not been paid out, and either contract owner or player is calling this function.
		require(block.timestamp - data.start >= ORACLIZEQUERYMAXTIME
			&& (msg.sender == OWNER || msg.sender == data.player)
			&& (!data.paidOut)
			&& data.etherReceived <= LIABILITIES);

		// set contract data
		slotsData[oraclizeQueryId].paidOut = true;

		LIABILITIES = SafeMath.sub(LIABILITIES, data.etherReceived);
		AMOUNTWAGERED = SafeMath.sub(AMOUNTWAGERED, data.etherReceived);
		// then transfer the original bet to the player.
		data.player.transfer(data.etherReceived);
		// finally, log an event saying that the refund has processed.
		Refund(oraclizeQueryId, data.etherReceived);
	}

	function play(uint8 credits) public payable {
		// save these for future use / gas efficiency
		uint256 betPerCredit = msg.value / credits;
		// require that the game is unpaused, and that the credits being purchased are greater than 0 and less than the allowed amount, default: 100 spins 
		// verify that the bet is less than or equal to the bet limit, so we don't go bankrupt, and that the etherreceived is greater than the minbet.

		require(!GAMEPAUSED
			&& msg.value > 0
			&& betPerCredit >= MINBET
			&& credits > 0 
			&& credits <= 224 //maximum number of spins is 84, must fit in 3 uint256's for logging.
			&& SafeMath.mul(betPerCredit, 5000) <= (SafeMath.mul(BANKROLL, MAXWIN_inTHOUSANDTHPERCENTS) / 1000)); // 5000 is the jackpot payout (max win on a roll)
		// if each bet is relatively small, we do not need to worry about miner cheating
		// we can resolve the bet in house with block.blockhash
		if (betPerCredit < MINBET_forORACLIZE){

			// save into memory for cheap access
			bytes32 blockHash = block.blockhash(block.number);

			// use dialsSpun as a nonce for the oraclize return random bytes.
			uint256 dialsSpun = DIALSSPUN;

			// dial1, dial2, dial3 are the items that the wheel lands on, represented by uints 0-6
			// these are then echoed to the front end by data1, data2, data3
			uint8 dial1;
			uint8 dial2;
			uint8 dial3;

			// these are used ONLY for log data for the frontend
			// each dial of the machine can be between 0 and 6 (see below table for distribution)
			// therefore, each dial takes 3 BITS of space -> uint(bits('111')) == 7, uint(bits('000')) == 0
			// so dataX can hold 256 bits/(3 bits * 3 dials) = 28.444 -> 28 spins worth of data 
			uint256[] memory data = new uint256[](8);

			// this is incremented every time a player hits a spot of the wheel that pays out
			// at the end this is multiplied by the betPerCredit amount to determine how much the game should payout.
			uint256 payout;
			// Now, loop over each credit.
			// Please note that this loop is almost identical to the loop in the __callback from oraclize
			// Modular-izing the loops into a single function is impossible because solidity can only store 16 variables into memory
			// also, it would cost increased gas for each spin.
			for (uint8 i = 0; i < credits; i++){

				// spin the first dial
				dialsSpun += 1;
				dial1 = uint8(uint(keccak256(blockHash, dialsSpun)) % 64);
				// spin the second dial
				dialsSpun += 1;
				dial2 = uint8(uint(keccak256(blockHash, dialsSpun)) % 64);
				// spin the third dial
				dialsSpun += 1;
				dial3 = uint8(uint(keccak256(blockHash, dialsSpun)) % 64);

				// calculate the result of the dials based on the hardcoded slot data: 

				// STOPS			REEL#1	REEL#2	REEL#3
				///////////////////////////////////////////
				// gold ether 	0 //  1  //  3   //   1  //	
				// silver ether 1 //  7  //  1   //   6  //
				// bronze ether 2 //  1  //  7   //   6  //
				// gold planet  3 //  5  //  7   //   6  //
				// silverplanet 4 //  9  //  6   //   7  //
				// bronzeplanet 5 //  9  //  8   //   6  //
				// ---blank---  6 //  32 //  32  //   32 //
				///////////////////////////////////////////

				// note that dial1/2/3 will go from mod 64 to mod 7 in this manner
				// I'd prefer to set different variable for mod 64 and for the actual dial value,
				// but I keep running into stack too deep exception (EVM can only have 16 vars stored in mem.)

				// dial 1, based on above table
				if (dial1 == 0) 							{ dial1 = 0; }
				else if (dial1 >= 1 && dial1 <= 7) 			{ dial1 = 1; }
				else if (dial1 == 8) 						{ dial1 = 2; }
				else if (dial1 >= 9 && dial1 <= 13) 		{ dial1 = 3; }
				else if (dial1 >= 14 && dial1 <= 22) 		{ dial1 = 4; }
				else if (dial1 >= 23 && dial1 <= 31) 		{ dial1 = 5; }
				else 										{ dial1 = 6; }

				// dial 2, based on above table
				if (dial2 >= 0 && dial2 <= 2) 				{ dial2 = 0; }
				else if (dial2 == 3) 						{ dial2 = 1; }
				else if (dial2 >= 4 && dial2 <= 10)			{ dial2 = 2; }
				else if (dial2 >= 11 && dial2 <= 17) 		{ dial2 = 3; }
				else if (dial2 >= 18 && dial2 <= 23) 		{ dial2 = 4; }
				else if (dial2 >= 24 && dial2 <= 31) 		{ dial2 = 5; }
				else 										{ dial2 = 6; }

				// dial 3, based on above table
				if (dial3 == 0) 							{ dial3 = 0; }
				else if (dial3 >= 1 && dial3 <= 6)			{ dial3 = 1; }
				else if (dial3 >= 7 && dial3 <= 12) 		{ dial3 = 2; }
				else if (dial3 >= 13 && dial3 <= 18)		{ dial3 = 3; }
				else if (dial3 >= 19 && dial3 <= 25) 		{ dial3 = 4; }
				else if (dial3 >= 26 && dial3 <= 31) 		{ dial3 = 5; }
				else 										{ dial3 = 6; }

				// hardcoded payouts data:
				// 			LANDS ON 				//	PAYS  //
				////////////////////////////////////////////////
				// Bronze E -> Silver E -> Gold E	//	5000  //
				// 3x Gold Ether					//	1777  //
				// 3x Silver Ether					//	250   //
				// 3x Bronze Ether					//	250   //
				//  3x any Ether 					//	95    // VARIABLE: default: 90, max: 100
				// Bronze P -> Silver P -> Gold P	//	90    //
				// 3x Gold Planet 					//	50    //
				// 3x Silver Planet					//	25    //
				// Any Gold P & Silver P & Bronze P //	20    //
				// 3x Bronze Planet					//	10    //
				// Any 3 planet type				//	3     //
				// Any 3 gold						//	3     //
				// Any 3 silver						//	2     //
				// Any 3 bronze						//	2     //
				// Blank, blank, blank				//	1     //
				// else								//  0     //
				////////////////////////////////////////////////

				// start the payouts for this wheel spin block
				// bronze ether -> silver ether -> gold ether 
				if (dial1 == 2 && dial2 == 1 && dial3 == 0)			{ payout += 5000; } // JACKPOT!!!!!!
				// all gold ether
				else if (dial1 == 0 && dial2 == 0 && dial3 == 0) 	{ payout += 1777; }
				// all silver ether 
				else if (dial1 == 1 && dial2 == 1 && dial3 == 1)	{ payout += 250; }
				// all bronze ether
				else if (dial1 == 2 && dial2 == 2 && dial3 == 2)	{ payout += 250; }
				// all some type of ether
				else if (dial1 >= 0 && dial1 <= 2 && dial2 >= 0 && dial2 <= 2 && dial3 >= 0 && dial3 <= 2)	{ payout += 95; }
				// bronze planet -> silver planet -> gold planet
				else if (dial1 == 5 && dial2 == 4 && dial3 == 3) 	{ payout += 90; }
				// all gold planet
				else if (dial1 == 3 && dial2 == 3 && dial3 == 3)	{ payout += 50; }
				// all silver planet
				else if (dial1 == 4 && dial2 == 4 && dial3 == 4)	{ payout += 25; }
				// a little complicated here, but this is the payout for one gold planet, one silver planet, one bronze planet, any order!
				else if ((dial1 == 3 && ((dial2 == 4 && dial3 == 5) || (dial2 == 5 && dial3 == 4)))
						|| (dial1 == 4 && ((dial2 == 3 && dial3 == 5) || (dial2 == 5 && dial3 == 3)))
						|| (dial1 == 5 && dial2 == 3 && dial3 == 4) ) {  // dial1 == 5 && dial2 == 4 && dial3 == 3 covered ^^^ with a better payout!

					payout += 20;
				}
				// all bronze planet 
				else if (dial1 == 5 && dial2 == 5 && dial3 == 5)	{ payout += 10; }
				// any three planet type 
				else if (dial1 >= 3 && dial1 <= 5 && dial2 >= 3 && dial2 <= 5 && dial3 >=3 && dial3 <= 5)	{ payout += 3; }
				// any three gold
				else if ((dial1 == 0 || dial1 == 3) && (dial2 == 0 && dial2 == 3) && (dial3 == 0 || dial3 == 3)) { payout += 3; }
				// any three silver
				else if ((dial1 == 1 || dial1 == 4) && (dial2 == 1 || dial2 == 4) && (dial3 == 1 || dial3 == 4)) { payout += 2; }
				// any three bronze 
				else if ((dial1 == 2 || dial1 == 5) && (dial2 == 2 || dial2 == 5) && (dial3 == 2 || dial3 == 5)) { payout += 2; }
				// all blank
				else if ( dial1 == 6 && dial2 == 6 && dial3 == 6) { payout += 1; }

				// Here we assemble uint256's of log data so that the frontend can "replay" the spins
				// each "dial" is a uint8 but can only be between 0-6, so would only need 3 bits to store this. uint(bits('111')) = 7
				// 2 ** 3 is the bitshift operator for three bits 
				if (i <= 27){
					// in data0
					data[0] += uint256(dial1) * uint256(2) ** (3 * ((3 * (27 - i)) + 2));
					data[0] += uint256(dial2) * uint256(2) ** (3 * ((3 * (27 - i)) + 1));
					data[0] += uint256(dial3) * uint256(2) ** (3 * ((3 * (27 - i))));
				}
				else if (i <= 55){
					// in data1
					data[1] += uint256(dial1) * uint256(2) ** (3 * ((3 * (55 - i)) + 2));
					data[1] += uint256(dial2) * uint256(2) ** (3 * ((3 * (55 - i)) + 1));
					data[1] += uint256(dial3) * uint256(2) ** (3 * ((3 * (55 - i))));
				}
				else if (i <= 83) {
					// in data2
					data[2] += uint256(dial1) * uint256(2) ** (3 * ((3 * (83 - i)) + 2));
					data[2] += uint256(dial2) * uint256(2) ** (3 * ((3 * (83 - i)) + 1));
					data[2] += uint256(dial3) * uint256(2) ** (3 * ((3 * (83 - i))));
				}
				else if (i <= 111) {
					// in data3
					data[3] += uint256(dial1) * uint256(2) ** (3 * ((3 * (111 - i)) + 2));
					data[3] += uint256(dial2) * uint256(2) ** (3 * ((3 * (111 - i)) + 1));
					data[3] += uint256(dial3) * uint256(2) ** (3 * ((3 * (111 - i))));
				}
				else if (i <= 139){
					// in data4
					data[4] += uint256(dial1) * uint256(2) ** (3 * ((3 * (139 - i)) + 2));
					data[4] += uint256(dial2) * uint256(2) ** (3 * ((3 * (139 - i)) + 1));
					data[4] += uint256(dial3) * uint256(2) ** (3 * ((3 * (139 - i))));
				}
				else if (i <= 167){
					// in data5
					data[5] += uint256(dial1) * uint256(2) ** (3 * ((3 * (167 - i)) + 2));
					data[5] += uint256(dial2) * uint256(2) ** (3 * ((3 * (167 - i)) + 1));
					data[5] += uint256(dial3) * uint256(2) ** (3 * ((3 * (167 - i))));
				}
				else if (i <= 195){
					// in data6
					data[6] += uint256(dial1) * uint256(2) ** (3 * ((3 * (195 - i)) + 2));
					data[6] += uint256(dial2) * uint256(2) ** (3 * ((3 * (195 - i)) + 1));
					data[6] += uint256(dial3) * uint256(2) ** (3 * ((3 * (195 - i))));
				}
				else if (i <= 223){
					// in data7
					data[7] += uint256(dial1) * uint256(2) ** (3 * ((3 * (223 - i)) + 2));
					data[7] += uint256(dial2) * uint256(2) ** (3 * ((3 * (223 - i)) + 1));
					data[7] += uint256(dial3) * uint256(2) ** (3 * ((3 * (223 - i))));
				}
			}

			// add these new dials to the storage variable DIALSSPUN
			DIALSSPUN = dialsSpun;
			// calculate amount for the developers fund.
			// this is: value of ether * (5% house edge) * (20% cut)
			uint256 developersCut = msg.value / 100;
			// add this to the developers fund.
			DEVELOPERSFUND = SafeMath.add(DEVELOPERSFUND, developersCut);
			// now payout ether
			uint256 etherPaidout = SafeMath.mul(betPerCredit, payout);
			// calculate amount won from the betPerCredit * payout amt
			// uint256 winAmount = data.etherReceived / data.credits * payout;
			
			// subtract the amount won from the bankroll, amount won := data.etherReceived / data.credits * payout
			// but I can't save this as a variable because the limit is 16 local variables because the EVM sucks
			// note: without safemath this is ```BANKROLL -= etherPaidout + developersCut - msg.value```
			BANKROLL = SafeMath.add(SafeMath.sub(BANKROLL, SafeMath.add(etherPaidout, developersCut)), msg.value);
			// and add the amount to the amount paid out storage variable
			AMOUNTPAIDOUT = SafeMath.add(AMOUNTPAIDOUT, etherPaidout);
			AMOUNTWAGERED = SafeMath.add(AMOUNTWAGERED, msg.value);
			// transfer the paidout amount to the player
			msg.sender.transfer(etherPaidout);
			
			// and lastly, log an event with the queryID of zero, because it was not from oraclize
			// log the data logs that were created above, we will not use event watchers here, but will use the txReceipt to get logs instead.
			// note that we do not make it super obvious how much was paid out
			// this game is meant to feel like the spins are calculated at the time of spin
			// even though this would be impossible without a massive wait time, and gas cost for each spin
			SlotsSmallBet(data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7]);

		}
		// if the bet amount is OVER the oraclize query limit, we must get the randomness from oraclize.
		// This is because miners are inventivized to interfere with the block.blockhash, in an attempt
		// to get more favorable rolls/slot spins/etc.
		else {
			// oraclize_newRandomDSQuery(delay in seconds, bytes of random data, gas for callback function)
			bytes32 oraclizeQueryId;
			if (credits <= 28){
			    oraclizeQueryId = oraclize_newRandomDSQuery(0, 30, 350000);
			    // add the amount bet to the bankroll, minus the gas spent on oraclize
				BANKROLL = SafeMath.sub(BANKROLL, SafeMath.mul(350000, ORACLIZEGASPRICE));
			}
			else if (credits <= 56){
			    oraclizeQueryId = oraclize_newRandomDSQuery(0, 30, 400000);

			    BANKROLL = SafeMath.sub(BANKROLL, SafeMath.mul(400000, ORACLIZEGASPRICE));
			}
			else if (credits <= 84){
			    oraclizeQueryId = oraclize_newRandomDSQuery(0, 30, 450000);

			    BANKROLL = SafeMath.sub(BANKROLL, SafeMath.mul(450000, ORACLIZEGASPRICE));
			}
			else if (credits <= 112){
				oraclizeQueryId = oraclize_newRandomDSQuery(0, 30, 500000);

			    BANKROLL = SafeMath.sub(BANKROLL, SafeMath.mul(500000, ORACLIZEGASPRICE));
			}
			else if (credits <= 140){
				oraclizeQueryId = oraclize_newRandomDSQuery(0, 30, 550000);

			    BANKROLL = SafeMath.sub(BANKROLL, SafeMath.mul(550000, ORACLIZEGASPRICE));
			}
			else if (credits <= 168){
				oraclizeQueryId = oraclize_newRandomDSQuery(0, 30, 600000);

			    BANKROLL = SafeMath.sub(BANKROLL, SafeMath.mul(600000, ORACLIZEGASPRICE));
			}
			else if (credits <= 196){
				oraclizeQueryId = oraclize_newRandomDSQuery(0, 30, 650000);

			    BANKROLL = SafeMath.sub(BANKROLL, SafeMath.mul(650000, ORACLIZEGASPRICE));
			}
			else {
				// credits <= 224
				oraclizeQueryId = oraclize_newRandomDSQuery(0, 30, 700000);

			    BANKROLL = SafeMath.sub(BANKROLL, SafeMath.mul(700000, ORACLIZEGASPRICE));
			    
			}
			// add the new slots data to a mapping so that the oraclize __callback can use it later
			slotsData[oraclizeQueryId] = SlotsGameData({
				player : msg.sender,
				paidOut : false,
				start : block.timestamp,
				etherReceived : msg.value,
				credits : credits
			});

			LIABILITIES = SafeMath.add(LIABILITIES, msg.value);
			AMOUNTWAGERED = SafeMath.add(AMOUNTWAGERED, msg.value);
			BuyCredits(oraclizeQueryId);
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
		// get the game data and put into memory
		SlotsGameData memory data = slotsData[_queryId];

		require(msg.sender == oraclize_cbAddress() 
			&& !data.paidOut 
			&& data.player != address(0) 
			&& LIABILITIES >= data.etherReceived);

		// if the proof has failed, immediately refund the player the original bet.
		
		/////////////////////////////////////////////////////////////////////////////
		// WARNING---THIS NEEDS TO BE REENABLED UPON DEPLOYMENT!!!!!!!!!!!
		/////////////////////////////////////////////////////////////////////////////

		// if (oraclize_randomDS_proofVerify__returnCode(_queryId, _result, _proof) != 0){
		if (0 != 0){
			// set contract data
			slotsData[_queryId].paidOut = true;

			LIABILITIES = SafeMath.sub(LIABILITIES, data.etherReceived);
			AMOUNTWAGERED = SafeMath.sub(AMOUNTWAGERED, data.etherReceived);
			// transfer the original bet
			data.player.transfer(data.etherReceived);
			// log these two events
			LedgerProofFailed(_queryId);
			Refund(_queryId, data.etherReceived);
		}
		else {
			// again, this block is almost identical to the previous block in the play(...) function 
			// instead of duplicating documentation, we will just point out the changes from the other block 
			uint256 dialsSpun = DIALSSPUN;
			
			uint8 dial1;
			uint8 dial2;
			uint8 dial3;
			
			uint256[] memory logsData = new uint256[](8);
			
			uint256 payout;
			
			// must use data.credits instead of credits.
			for (uint8 i = 0; i < data.credits; i++){

				// all dials now use _result, instead of blockhash, this is the main change, and allows Moon Mission Slots to 
				// accomodate bets of any size, free of possible miner interference 
				dialsSpun += 1;
				dial1 = uint8(uint(keccak256(_result, dialsSpun)) % 64);
				
				dialsSpun += 1;
				dial2 = uint8(uint(keccak256(_result, dialsSpun)) % 64);
				
				dialsSpun += 1;
				dial3 = uint8(uint(keccak256(_result, dialsSpun)) % 64);

				// dial 1
				if (dial1 == 0) 							{ dial1 = 0; }
				else if (dial1 >= 1 && dial1 <= 7) 			{ dial1 = 1; }
				else if (dial1 == 8) 						{ dial1 = 2; }
				else if (dial1 >= 9 && dial1 <= 13) 		{ dial1 = 3; }
				else if (dial1 >= 14 && dial1 <= 22) 		{ dial1 = 4; }
				else if (dial1 >= 23 && dial1 <= 31) 		{ dial1 = 5; }
				else 										{ dial1 = 6; }

				// dial 2
				if (dial2 >= 0 && dial2 <= 2) 				{ dial2 = 0; }
				else if (dial2 == 3) 						{ dial2 = 1; }
				else if (dial2 >= 4 && dial2 <= 10)			{ dial2 = 2; }
				else if (dial2 >= 11 && dial2 <= 17) 		{ dial2 = 3; }
				else if (dial2 >= 18 && dial2 <= 23) 		{ dial2 = 4; }
				else if (dial2 >= 24 && dial2 <= 31) 		{ dial2 = 5; }
				else 										{ dial2 = 6; }

				// dial 3
				if (dial3 == 0) 							{ dial3 = 0; }
				else if (dial3 >= 1 && dial3 <= 6)			{ dial3 = 1; }
				else if (dial3 >= 7 && dial3 <= 12) 		{ dial3 = 2; }
				else if (dial3 >= 13 && dial3 <= 18)		{ dial3 = 3; }
				else if (dial3 >= 19 && dial3 <= 25) 		{ dial3 = 4; }
				else if (dial3 >= 26 && dial3 <= 31) 		{ dial3 = 5; }
				else 										{ dial3 = 6; }

				
				// payouts (still labelled)

				// bronze ether -> silver ether -> gold ether 
				if (dial1 == 2 && dial2 == 1 && dial3 == 0)			{ payout += 10000; } // JACKPOT!!!!!!
				// all gold ether
				else if (dial1 == 0 && dial2 == 0 && dial3 == 0) 	{ payout += 1500; }
				// all silver ether 
				else if (dial1 == 1 && dial2 == 1 && dial3 == 1)	{ payout += 250; }
				// all bronze ether
				else if (dial1 == 2 && dial2 == 2 && dial3 == 2)	{ payout += 250; }
				// all some type of ether
				else if (dial1 >= 0 && dial1 <= 2 && dial2 >= 0 && dial2 <= 2 && dial3 >= 0 && dial3 <= 2)	{ payout += 90; }	// any ether, variable payout to adjust house edge. MAX == 100, DEFAULT == 90
				// bronze planet -> silver planet -> gold planet
				else if (dial1 == 5 && dial2 == 4 && dial3 == 3) 	{ payout += 100; }
				// all gold planet
				else if (dial1 == 3 && dial2 == 3 && dial3 == 3)	{ payout += 50; }
				// all silver planet
				else if (dial1 == 4 && dial2 == 4 && dial3 == 4)	{ payout += 25; }
				// a little complicated here, but this is the payout for one gold planet, one silver planet, one bronze planet, any order!
				else if ((dial1 == 3 && ((dial2 == 4 && dial3 == 5) || (dial2 == 5 && dial3 == 4)))
						|| (dial1 == 4 && ((dial2 == 3 && dial3 == 5) || (dial2 == 5 && dial3 == 3)))
						|| (dial1 == 5 && dial2 == 3 && dial3 == 4) ) {  // dial1 == 5 && dial2 == 4 && dial3 == 3 covered ^^^ with a better payout!

					payout += 20;
				}
				// all bronze planet 
				else if (dial1 == 5 && dial2 == 5 && dial3 == 5)	{ payout += 10; }
				// any three planet type 
				else if (dial1 >= 3 && dial1 <= 5 && dial2 >= 3 && dial2 <= 5 && dial3 >=3 && dial3 <= 5)	{ payout += 3; }
				// any three gold
				else if ((dial1 == 0 || dial1 == 3) && (dial2 == 0 && dial2 == 3) && (dial3 == 0 || dial3 == 3)) { payout += 3; }
				// any three silver
				else if ((dial1 == 1 || dial1 == 4) && (dial2 == 1 || dial2 == 4) && (dial3 == 1 || dial3 == 4)) { payout += 2; }
				// any three bronze 
				else if ((dial1 == 2 || dial1 == 5) && (dial2 == 2 || dial2 == 5) && (dial3 == 2 || dial3 == 5)) { payout += 2; }
				// all blank
				else if ( dial1 == 6 && dial2 == 6 && dial3 == 6) { payout += 1; }

				// assembling log data
				if (i <= 27){
					// in logsData0
					logsData[0] += uint256(dial1) * uint256(2) ** (3 * ((3 * (27 - i)) + 2));
					logsData[0] += uint256(dial2) * uint256(2) ** (3 * ((3 * (27 - i)) + 1));
					logsData[0] += uint256(dial3) * uint256(2) ** (3 * ((3 * (27 - i))));
				}
				else if (i <= 55){
					// in logsData1
					logsData[1] += uint256(dial1) * uint256(2) ** (3 * ((3 * (55 - i)) + 2));
					logsData[1] += uint256(dial2) * uint256(2) ** (3 * ((3 * (55 - i)) + 1));
					logsData[1] += uint256(dial3) * uint256(2) ** (3 * ((3 * (55 - i))));
				}
				else if (i <= 83) {
					// in logsData2
					logsData[2] += uint256(dial1) * uint256(2) ** (3 * ((3 * (83 - i)) + 2));
					logsData[2] += uint256(dial2) * uint256(2) ** (3 * ((3 * (83 - i)) + 1));
					logsData[2] += uint256(dial3) * uint256(2) ** (3 * ((3 * (83 - i))));
				}
				else if (i <= 111) {
					// in logsData3
					logsData[3] += uint256(dial1) * uint256(2) ** (3 * ((3 * (111 - i)) + 2));
					logsData[3] += uint256(dial2) * uint256(2) ** (3 * ((3 * (111 - i)) + 1));
					logsData[3] += uint256(dial3) * uint256(2) ** (3 * ((3 * (111 - i))));
				}
				else if (i <= 139){
					// in logsData4
					logsData[4] += uint256(dial1) * uint256(2) ** (3 * ((3 * (139 - i)) + 2));
					logsData[4] += uint256(dial2) * uint256(2) ** (3 * ((3 * (139 - i)) + 1));
					logsData[4] += uint256(dial3) * uint256(2) ** (3 * ((3 * (139 - i))));
				}
				else if (i <= 167){
					// in logsData5
					logsData[5] += uint256(dial1) * uint256(2) ** (3 * ((3 * (167 - i)) + 2));
					logsData[5] += uint256(dial2) * uint256(2) ** (3 * ((3 * (167 - i)) + 1));
					logsData[5] += uint256(dial3) * uint256(2) ** (3 * ((3 * (167 - i))));
				}
				else if (i <= 195){
					// in logsData6
					logsData[6] += uint256(dial1) * uint256(2) ** (3 * ((3 * (195 - i)) + 2));
					logsData[6] += uint256(dial2) * uint256(2) ** (3 * ((3 * (195 - i)) + 1));
					logsData[6] += uint256(dial3) * uint256(2) ** (3 * ((3 * (195 - i))));
				}
				else if (i <= 223){
					// in logsData7
					logsData[7] += uint256(dial1) * uint256(2) ** (3 * ((3 * (223 - i)) + 2));
					logsData[7] += uint256(dial2) * uint256(2) ** (3 * ((3 * (223 - i)) + 1));
					logsData[7] += uint256(dial3) * uint256(2) ** (3 * ((3 * (223 - i))));
				}
			}

			DIALSSPUN = dialsSpun;

			uint256 etherPaidout = SafeMath.mul((data.etherReceived / data.credits), payout);
			uint256 developersCut = data.etherReceived / 100;

			DEVELOPERSFUND = SafeMath.add(DEVELOPERSFUND, developersCut);

			LIABILITIES = SafeMath.sub(LIABILITIES, data.etherReceived);
			// note: without safemath this is ```BANKROLL = BANKROLL + data.etherReceived - (etherPaidout + developersCut)```
			BANKROLL = SafeMath.sub(SafeMath.add(BANKROLL, data.etherReceived), SafeMath.add(etherPaidout, developersCut));
			
			AMOUNTPAIDOUT = SafeMath.add(AMOUNTPAIDOUT, etherPaidout);

			// IMPORTANT: we must change the "paidOut" to TRUE here to prevent reentrancy/other nasty effects.
			// this was not needed with the previous loop/code block, and is used because variables must be written into storage
			// with the oraclize __callbacks
			slotsData[_queryId].paidOut = true;
			// now, transfer the paidOut amount (use data to get these variable as before)
			data.player.transfer(etherPaidout);

			SlotsLargeBet(_queryId, logsData[0], logsData[1], logsData[2], logsData[3], logsData[4], logsData[5], logsData[6], logsData[7]);
		}
	}

}