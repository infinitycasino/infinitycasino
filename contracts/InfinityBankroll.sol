pragma solidity ^0.4.18;

import "./SafeMath.sol";

contract InfinityCasinoGameInterface {
	uint256 public DEVELOPERSFUND;
	uint256 public LIABILITIES;
	function payDevelopersFund(address developer) public;
	function receivePaymentForOraclize() payable public;
	function getMaxWin() public view returns(uint256);
}

contract InfinityCasinoBankrollInterface {
	function payEtherToWinner(uint256 amtEther, address winner) public;
	function receiveEtherFromGameAddress() payable public;
	function payOraclize(uint256 amountToPay) public;
	function getBankroll() public view returns(uint256);
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

contract InfinityBankroll is ERC20, InfinityCasinoBankrollInterface {

	using SafeMath for *;

	// constants for InfinityBankroll

	address public OWNER;
	uint256 public MAXIMUMINVESTMENTSALLOWED;
	uint256 public WAITTIMEUNTILWITHDRAWORTRANSFER;
	uint256 public DEVELOPERSFUND;

	// this will be initialized as the trusted game addresses which will forward their ether
	// to the bankroll contract, and when players win, they will request the bankroll contract 
	// to send these players their winnings.
	// Feel free to audit these contracts on etherscan...
	address[2] public TRUSTEDADDRESSES;

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

	// events
	event FundBankroll(address contributor, uint256 etherContributed, uint256 tokensReceived);
	event CashOut(address contributor, uint256 etherWithdrawn, uint256 tokensCashedIn);

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

		// 100 tokens/ether is the inital seed amount, so:
		uint256 initialTokens = msg.value * 100;
		balances[msg.sender] = initialTokens;
		totalSupply += initialTokens;

		// log a mint tokens event
		Transfer(0x0, msg.sender, initialTokens);

		// insert given game addresses into the TRUSTEDADDRESSES[] array
		TRUSTEDADDRESSES[0] = dice;
		TRUSTEDADDRESSES[1] = slots;

		////////////////////////////////////////////////
		// CHANGE TO 6 HOURS ON LIVE DEPLOYMENT
		////////////////////////////////////////////////
		WAITTIMEUNTILWITHDRAWORTRANSFER = 0 seconds;
		MAXIMUMINVESTMENTSALLOWED = 100 ether;
	}

	///////////////////////////////////////////////
	// VIEW FUNCTIONS -> mainly for frontend
	/////////////////////////////////////////////// 

	function checkWhenContributorCanTransferOrWithdraw(address bankrollerAddress) view public returns(uint256){
		return contributionTime[bankrollerAddress];
	}

	function getBankroll() view public returns(uint256){
		// returns the total balance minus the developers fund, as the amount of active bankroll
		return SafeMath.sub(this.balance, DEVELOPERSFUND);
	}

	///////////////////////////////////////////////
	// BANKROLL CONTRACT <-> GAME CONTRACTS functions
	/////////////////////////////////////////////// 

	function payEtherToWinner(uint256 amtEther, address winner) public addressInTrustedAddresses(msg.sender){
		// this function will get called by a game contract when someone wins a game
		// note, a failed transfer to a player will propagate the OP_REVERT.

		winner.transfer(amtEther);
	}

	function receiveEtherFromGameAddress() payable public addressInTrustedAddresses(msg.sender) {
		// this function will get called from the game contracts when someone starts a game.
	}

	function payOraclize(uint256 amountToPay) public addressInTrustedAddresses(msg.sender) {
		// this function will get called when a game contract must pay payOraclize
		InfinityCasinoGameInterface(msg.sender).receivePaymentForOraclize.value(amountToPay)();
	}

	///////////////////////////////////////////////
	// BANKROLL CONTRACT MAIN FUNCTIONS
	///////////////////////////////////////////////


	// this function ADDS to the bankroll of infinity casino, and credits the bankroller a proportional
	// amount of tokens so they may withdraw their tokens later
	// also if there is only a limited amount of space left in the bankroll, a user can just send as much 
	// ether as they want, because they will be able to contribute up to the maximum, and then get refunded the rest.
	function () public payable {

		// save in memory for cheap access.
		// this represents the total bankroll balance before the function was called.
		uint256 currentTotalBankroll = getBankroll() - msg.value;

		require(currentTotalBankroll < MAXIMUMINVESTMENTSALLOWED && msg.value != 0);

		uint256 currentSupplyOfTokens = totalSupply;
		uint256 contributedEther;

		bool contributionTakesBankrollOverLimit;
		uint256 ifContributionTakesBankrollOverLimit_Refund;

		if (SafeMath.add(currentTotalBankroll, msg.value) > MAXIMUMINVESTMENTSALLOWED){
			// allow the bankroller to contribute up to the allowed amount of ether, and refund the rest.
			contributionTakesBankrollOverLimit = true;
			// set contributed ether as (MAXIMUMINVESTMENTSALLOWED - BANKROLL)
			contributedEther = SafeMath.sub(MAXIMUMINVESTMENTSALLOWED, currentTotalBankroll);
			// refund the rest of the ether, which is (original amount sent - (maximum amount allowed - bankroll))
			ifContributionTakesBankrollOverLimit_Refund = SafeMath.sub(msg.value, contributedEther);
		}
		else {
			contributedEther = msg.value;
		}

        uint256 creditedTokens;
        
		if (currentSupplyOfTokens != 0){
			// determine the ratio of contribution versus total BANKROLL.
			creditedTokens = SafeMath.mul(contributedEther, currentSupplyOfTokens) / currentTotalBankroll;
		}
		else {
			// edge case where ALL money was cashed out from bankroll
			// so currentSupplyOfTokens == 0
			// currentTotalBankroll can == 0 or not, if someone mines/sefldestruct's to the contract
			// but either way, give all the bankroll to person who deposits ether
			creditedTokens = SafeMath.mul(contributedEther, 100);
		}
		
		// now update the total supply of tokens and bankroll amount
		totalSupply = SafeMath.add(currentSupplyOfTokens, creditedTokens);

		// now credit the user with his amount of contributed tokens 
		balances[msg.sender] = SafeMath.add(balances[msg.sender], creditedTokens);

		// update his contribution time for stake time locking
		contributionTime[msg.sender] = block.timestamp;

		// now look if the attempted contribution would have taken the BANKROLL over the limit, 
		// and if true, refund the excess ether.
		if (contributionTakesBankrollOverLimit){
			msg.sender.transfer(ifContributionTakesBankrollOverLimit_Refund);
		}

		// log an event about funding bankroll
		FundBankroll(msg.sender, contributedEther, creditedTokens);

		// log a mint tokens event
		Transfer(0x0, msg.sender, creditedTokens);
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
		// again, represents the total balance of the contract before the function was called.
		uint256 currentTotalBankroll = getBankroll();
		uint256 currentSupplyOfTokens = totalSupply;

		// calculate the token withdraw ratio based on current supply 
		uint256 withdrawEther = SafeMath.mul(_amountTokens, currentTotalBankroll) / currentSupplyOfTokens;

		// developers take 1% of withdrawls 
		uint256 developersCut = withdrawEther / 100;
		uint256 contributorAmount = SafeMath.sub(withdrawEther, developersCut);

		// now update the total supply of tokens by subtracting the tokens that are being "cashed in"
		totalSupply = SafeMath.sub(currentSupplyOfTokens, _amountTokens);

		// and update the users supply of tokens 
		balances[msg.sender] = SafeMath.sub(tokenBalance, _amountTokens);

		// update the developers fund based on this calculated amount 
		DEVELOPERSFUND = SafeMath.add(DEVELOPERSFUND, developersCut);

		// lastly, transfer the ether back to the bankroller. Thanks for your contribution!
		msg.sender.transfer(contributorAmount);

		// log an event about cashout
		CashOut(msg.sender, contributorAmount, _amountTokens);

		// log a destroy tokens event
		Transfer(msg.sender, 0x0, _amountTokens);
	}

	function cashoutINFSTokens_ALL() public {

		// just forward to cashoutINFSTokens with input as the senders entire balance
		cashoutINFSTokens(balances[msg.sender]);
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

	function transfer(address _to, uint256 _value) public returns (bool success){
		if (balances[msg.sender] >= _value 
			&& _value > 0 
			&& contributionTime[msg.sender] + WAITTIMEUNTILWITHDRAWORTRANSFER <= block.timestamp
			&& _to != address(this)){

			// safely subtract
			balances[msg.sender] = SafeMath.sub(balances[msg.sender], _value);
			balances[_to] = SafeMath.add(balances[_to], _value);

			// log event 
			Transfer(msg.sender, _to, _value);
			return true;
		}
		else {
			return false;
		}
	}

	function transferFrom(address _from, address _to, uint _value) public returns(bool){
		if (allowed[_from][msg.sender] >= _value 
			&& balances[_from] >= _value 
			&& _value > 0 
			&& contributionTime[_from] + WAITTIMEUNTILWITHDRAWORTRANSFER <= block.timestamp
			&& _to != address(this)){

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
		Approval(msg.sender, _spender, _value);
		// log event
		return true;
	}
	
	function allowance(address _owner, address _spender) constant public returns(uint){
		return allowed[_owner][_spender];
	}
}