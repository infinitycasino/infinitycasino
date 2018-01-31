pragma solidity ^0.4.18;

import "./SafeMath.sol";

contract InfinityCasinoGameInterface {
	uint256 public BANKROLL;
	uint256 public DEVELOPERSFUND;
	function acceptEtherFromBankrollContract() payable public;
	function payEtherToBankrollContract(uint256 amountToSend) public;
	function payDevelopersFund(address developer) public;
}

contract ERC20 {
	function totalSupply() constant public returns (uint supply);
	function balanceOf(address _owner) constant public returns (uint balance);
	function transfer(address _to, uint _value) public returns (bool success);
	function transferFrom(address _from, address _to, uint _value) public returns (bool success);
	function approve(address _spender, uint _value) public returns (bool success);
	function allowance(address _owner, address _spender) constant public returns (uint remaining);
	event Transfer(address indexed _from, address indexed _to, uint _value);
	event Approval(address indexed _owner, address indexed _spender, uint _value);
}

contract InfinityBankroll is ERC20 {

	using SafeMath for *;

	// constants for InfinityBankroll

	address public OWNER;
	uint256 public BANKROLL;
	uint256 public MAXIMUMINVESTMENTSALLOWED;
	uint256 public WAITTIMEUNTILWITHDRAWORTRANSFER;
	uint256 public DEVELOPERSFUND;

	// this will be initialized as the trusted game addresses which will forward their ether
	// to the bankroll contract, and when players win, they will request the bankroll contract 
	// to send these players their winnings.
	// Feel free to audit these contracts on etherscan...
	address[2] public TRUSTEDADDRESSES;
	mapping(address => uint256) trustedAddressTargetAmount;

	// mapping to log the last time a user contributed to the bankroll 
	mapping(address => uint256) contributionTime;

	// constants for ERC20 standard
	string public constant name = "Infinity Shares";
	string public constant symbol = "INFS";
	uint8 public constant decimals = 18;
	// variable total supply
	uint256 public totalSupply;

	// mapping to store tokens
	mapping(address => uint256) balances;
	mapping(address => mapping(address => uint256)) allowed;

	/////////////////
	// CONTRACT LOGIC
	/////////////////

	// events
	event FundBankroll(address contributor, uint256 etherContributed, uint256 tokensReceived);
	event CashOut(address contributor, uint256 etherWithdrawn, uint256 tokensCashedIn);
	event HERE(uint8 num);

	// checks that an address is a "trusted address of a legitimate infinity casino game"
	modifier addressInTrustedAddresses(address thisAddress){

		require(TRUSTEDADDRESSES[0] == thisAddress || TRUSTEDADDRESSES[1] == thisAddress);
		_;
	}

	// initialization function 
	function InfinityBankroll(address dice, address slots) public payable {
		// function is payable, owner of contract MUST "seed" contract with some ether, 
		// so that the ratios are correct when tokens are being minted
		require (msg.value > 0);

		OWNER = msg.sender;

		// update bankroll 
		BANKROLL = msg.value;
		// 100 tokens/ether is the inital seed amount, so:
		uint256 initialTokens = msg.value * 100;
		balances[msg.sender] = initialTokens;
		totalSupply += initialTokens;

		// insert given game addresses into the TRUSTEDADDRESSES[] array
		TRUSTEDADDRESSES[0] = dice;
		TRUSTEDADDRESSES[1] = slots;

		// please note that these will be the GAME ADDRESSES which will forward their balances to the bankroll, and request to pay bettors from the bankroll.
		trustedAddressTargetAmount[TRUSTEDADDRESSES[0]] = 5 ether;
		trustedAddressTargetAmount[TRUSTEDADDRESSES[1]] = 5 ether;
		// CHANGE TO 6 HOURS ON LIVE DEPLOYMENT
		WAITTIMEUNTILWITHDRAWORTRANSFER = 0 seconds;
		MAXIMUMINVESTMENTSALLOWED = 10 ether;
	}

	///////////////////////////////////////////////
	// VIEW FUNCTIONS -> mainly for frontend
	/////////////////////////////////////////////// 

	function checkAmountAllocatedToGame(address gameAddress) view public returns(uint256) {
		return trustedAddressTargetAmount[gameAddress];
	}

	function checkWhenContributorCanTransferOrWithdraw(address bankrollerAddress) view public returns(uint256){
		return contributionTime[bankrollerAddress];
	}


	///////////////////////////////////////////////
	// BANKROLL CONTRACT -> GAME CONTRACT functions
	/////////////////////////////////////////////// 

	// get sum(current balances) from all games and this contract 
	function getCurrentBalances() view public returns(uint256) {
		uint256 totalBalances = BANKROLL;
		// loop through all trusted addresses, and get their balances 
		totalBalances += InfinityCasinoGameInterface(TRUSTEDADDRESSES[0]).BANKROLL();
		totalBalances += InfinityCasinoGameInterface(TRUSTEDADDRESSES[1]).BANKROLL();

		return totalBalances;
	}

	// this function ADDS to the bankroll of infinity casino, and credits the bankroller a proportional
	// amount of tokens so they may withdraw their tokens later
	// also if there is only a limited amount of space left in the bankroll, a user can just send as much 
	// ether as they want, because they will be able to contribute up to the maximum, and then get refunded the rest.
	function () public payable {
		// save these in memory for cheap access.
		uint256 currentTotalBankroll = getCurrentBalances();

		require(currentTotalBankroll < MAXIMUMINVESTMENTSALLOWED);

		uint256 currentContractBankroll = BANKROLL;
		uint256 currentSupplyOfTokens = totalSupply;
		uint256 contributedEther = msg.value;

		bool contributionTakesBankrollOverLimit;
		uint256 ifContributionTakesBankrollOverLimit_Refund;

		if (SafeMath.add(currentTotalBankroll, contributedEther) > MAXIMUMINVESTMENTSALLOWED){
			// allow the bankroller to contribute up to the allowed amount of ether, and refund the rest.
			contributionTakesBankrollOverLimit = true;
			// set contributed ether as (MAXIMUMINVESTMENTSALLOWED - BANKROLL)
			contributedEther = SafeMath.sub(MAXIMUMINVESTMENTSALLOWED, currentTotalBankroll);
			// refund the rest of the ether, which is (original amount sent - (maximum amount allowed - bankroll))
			ifContributionTakesBankrollOverLimit_Refund = SafeMath.sub(msg.value, contributedEther);
		}

		// determine the ratio of contribution versus total BANKROLL.
		uint256 creditedTokens = SafeMath.mul(contributedEther, currentSupplyOfTokens) / currentTotalBankroll;

		// now update the total supply of tokens and bankroll amount
		totalSupply = SafeMath.add(currentSupplyOfTokens, creditedTokens);
		BANKROLL = SafeMath.add(currentContractBankroll, contributedEther);

		// now credit the user with his amount of contributed tokens 
		balances[msg.sender] = SafeMath.add(balances[msg.sender], creditedTokens);
		contributionTime[msg.sender] = block.timestamp;

		// now look if the attempted contribution would have taken the BANKROLL over the limit, 
		// and if true, refund the excess ether.
		if (contributionTakesBankrollOverLimit){
			msg.sender.transfer(ifContributionTakesBankrollOverLimit_Refund);
		}

		// log an event
		FundBankroll(msg.sender, contributedEther, creditedTokens);
	}

	function cashoutINFSTokens(uint256 _amountTokens) public {
		// In effect, this function is the OPPOSITE of the un-named payable function above^^^
		// this allows bankrollers to "cash out" at any time, and receive the ether that they contributed, PLUS
		// a proportion of any ether that was earned by the smart contact when their ether was "staking", However
		// this works in reverse as well. Any net losses of the smart contract will be absorbed by the player in like manner.
		// Of course, due to the constant house edge, a bankroller that leaves their ether in the contract long enough
		// is effectively guaranteed to withdraw more ether than they originally "staked"

		// save in memory for cheap access.
		uint256 tokenBalance = balances[msg.sender];
		// verify that the contributor has enough tokens to cash out this many, and has waited the required time.
		require(_amountTokens <= tokenBalance 
			&& contributionTime[msg.sender] + WAITTIMEUNTILWITHDRAWORTRANSFER <= block.timestamp
			&& _amountTokens > 0);

		// save in memory for cheap access.
		uint256 currentContractBankroll = BANKROLL;
		uint256 currentTotalBankroll = getCurrentBalances();
		uint256 currentSupplyOfTokens = totalSupply;

		// calculate the token withdraw ratio based on current supply 
		uint256 withdrawEther = SafeMath.mul(_amountTokens, currentTotalBankroll) / currentSupplyOfTokens;
		// now verify that this requested amount of ether is contained in the bankroll contract...
		require(withdrawEther <= currentContractBankroll);

		// developers take 1% of withdrawls 
		uint256 developersCut = withdrawEther / 100;
		uint256 contributorAmount = SafeMath.sub(withdrawEther, developersCut);

		// now update the total supply of tokens by subtracting the tokens that are being "cashed in"
		totalSupply = SafeMath.sub(currentSupplyOfTokens, _amountTokens);
		// and update the users supply of tokens 
		balances[msg.sender] = SafeMath.sub(tokenBalance, _amountTokens);

		// update the bankroll based on the withdrawn amount.
		BANKROLL = SafeMath.sub(currentContractBankroll, withdrawEther);
		// update the developers fund based on this calculated amount 
		DEVELOPERSFUND = SafeMath.add(DEVELOPERSFUND, developersCut);

		// lastly, transfer the ether back to the bankroller. Thanks for your contribution!
		msg.sender.transfer(contributorAmount);

		// log an event
		CashOut(msg.sender, contributorAmount, _amountTokens);
	}

	////////////////////
	// OWNER FUNCTIONS:
	////////////////////
	// Please, be aware that the owner ONLY can change:
		// 1. The owner can increase or decrease the target amount for a game. They can then call the updater function to give/receive the ether from the game.
		// 1. The wait time until a user can withdraw or transfer their tokens after purchase through the default function above ^^^
		// 2. The owner can change the maximum amount of investments allowed. This allows for early contributors to guarantee
		// 		a certain percentage of the bankroll so that their stake cannot be diluted immediately. However, be aware that the 
		//		maximum amount of investments allowed will be raised over time. This will allow for higher bets by gamblers, resulting
		// 		in higher dividends for the bankrollers
		// 3. The owner can freeze payouts to bettors. This will be used in case of an emergency, and the contract will reject all
		//		new bets as well. This does not mean that bettors will lose their money without recompense. They will be allowed to call the 
		// 		"refund" function in the respective game smart contract once payouts are un-frozen.
		// 4. Finally, the owner can modify and withdraw the developers reward, which will fund future development, including new games, a sexier frontend,
		// 		and TRUE DAO governance so that onlyOwner functions don't have to exist anymore ;) and in order to effectively react to changes 
		// 		in the market (lower the percentage because of increased competition in the blockchain casino space, etc.)

	function transferOwnership(address newOwner) public {
		require(msg.sender == OWNER);

		OWNER = newOwner;
	}

	function changeTargetGameFunds(uint256 funds, address gameAddress) public addressInTrustedAddresses(gameAddress) {
		require(msg.sender == OWNER);

		trustedAddressTargetAmount[gameAddress] = funds;
	}

	function assessBankrollOfGame(address gameAddress) private {

		uint256 gameBalance = InfinityCasinoGameInterface(gameAddress).BANKROLL();
		uint256 suggestedBalance = trustedAddressTargetAmount[gameAddress];
		
		// if the game has made money, then send a call to the game requesting that the game sends excess balance to the bankroll 
		if (gameBalance > suggestedBalance) {
			// calculate the amount that the contract must pay 
			uint256 mustPay = SafeMath.sub(gameBalance, suggestedBalance);
			// force the game contract to pay this amount of ether 
			InfinityCasinoGameInterface(gameAddress).payEtherToBankrollContract(mustPay);
			// BANKROLL does not need to be incremented, it already does in receiveEtherFromGameAddress()
		}
		// reload bankroll with ether.
		else if (suggestedBalance > gameBalance){
			// calulate the amount the contract must give, in ether.
			uint256 mustGive = SafeMath.sub(suggestedBalance, gameBalance);
			// give this contract ether, to it's correct function 
			InfinityCasinoGameInterface(gameAddress).acceptEtherFromBankrollContract.value(mustGive)();
			
			// decrease BANKROLL by the amount given out 
			BANKROLL = SafeMath.sub(BANKROLL, mustGive);
		}
		// if suggestedBalance == gameBalance, then do nothing
	}

	// use the above function, but just loop through all games.
	function assessBankrollOfAllGames() public {
		require(msg.sender == OWNER);

		assessBankrollOfGame(TRUSTEDADDRESSES[0]);
		assessBankrollOfGame(TRUSTEDADDRESSES[1]);
	}

	function receiveEtherFromGameAddress() payable public addressInTrustedAddresses(msg.sender) {
		// this function will get called from the game contracts, and just sends ether to the main contract and increments the bankroll.
		BANKROLL = SafeMath.add(BANKROLL, msg.value);
	}

	function changeWaitTimeUntilWithdrawOrTransfer(uint256 waitTime) public {
		// waitTime MUST be less than or equal to 10 weeks
		require (msg.sender == OWNER && waitTime <= 6048000);

		WAITTIMEUNTILWITHDRAWORTRANSFER = waitTime;
	}

	function changeMaximumInvestmentsAllowed(uint256 maxAmount) public {
		require(msg.sender == OWNER);

		MAXIMUMINVESTMENTSALLOWED = maxAmount;
	}


	function withdrawDevelopersFund(address receiver) public {
		require(msg.sender == OWNER);

		// first get developers fund from each game 
        InfinityCasinoGameInterface(TRUSTEDADDRESSES[0]).payDevelopersFund(receiver);
		InfinityCasinoGameInterface(TRUSTEDADDRESSES[1]).payDevelopersFund(receiver);

		// now send the developers fund from the main contract.
		uint256 developersFund = DEVELOPERSFUND;

		// set developers fund to zero
		DEVELOPERSFUND = 0;

		// transfer this amount to the owner!
		receiver.transfer(developersFund);
	}

	// Can be removed after some testing...
	function emergencySelfDestruct() public {
		require(msg.sender == OWNER);

		selfdestruct(msg.sender);
	}

	///////////////////////////////
	// BASIC ERC20 TOKEN OPERATIONS
	///////////////////////////////

	function totalSupply() constant public returns(uint){
		return totalSupply;
	}

	function balanceOf(address _owner) constant public returns(uint){
		return balances[_owner];
	}

	function transfer(address _to, uint256 _value) public returns (bool){
		if (balances[msg.sender] >= _value 
			&& _value > 0 
			&& contributionTime[msg.sender] + WAITTIMEUNTILWITHDRAWORTRANSFER <= block.timestamp){
			// safely subtract
			balances[msg.sender] = SafeMath.sub(balances[msg.sender], _value);
			balances[_to] = SafeMath.add(balances[_to], _value);
			// log event 
			Transfer(msg.sender, _to, _value);
		}
		else {
			return false;
		}
	}

	function transferFrom(address _from, address _to, uint _value) public returns(bool){
		if (allowed[_from][msg.sender] >= _value 
			&& balances[_from] >= _value 
			&& _value > 0 
			&& contributionTime[_from] + WAITTIMEUNTILWITHDRAWORTRANSFER <= block.timestamp){
			// safely add to _to and subtract from _from, and subtract from allowed balances.
			balances[_to] = SafeMath.add(balances[_to], _value);
    		balances[_from] = SafeMath.sub(balances[_from], _value);
    		allowed[_from][msg.sender] = SafeMath.sub(allowed[_from][msg.sender], _value);
    		// log event
    		Transfer(_from, _to, _value);
    		return true;
   		} 
    	else { 
    		return false;
    	}
	}
	
	function approve(address _spender, uint _value) public returns(bool){
		require(_value > 0);
		allowed[msg.sender][_spender] = _value;
		// log event
		Approval(msg.sender, _spender, _value);
		return true;
	}
	
	function allowance(address _owner, address _spender) constant public returns(uint){
		return allowed[_owner][_spender];
	}
}