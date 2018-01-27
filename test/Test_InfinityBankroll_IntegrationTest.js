var InfinityBankroll = artifacts.require("InfinityBankroll");
var Dice = artifacts.require("InfinityDice_WithBankroller_NoOraclize");
var Slots = artifacts.require("MoonMissionSlots_WithBankroller_NoOraclize");

contract("Test_InfinityBankroll_IntegrationTest", function(accounts){

	it("should deploy bankroll & send 11 ether, and update ether/token balances", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);

		assert(String(await bankroll.BANKROLL.call()) === String(web3.toWei(11, "ether")), "ether transfer did not register");
		assert(String(await bankroll.totalSupply.call()) === String(100 * web3.toWei(11, "ether")), "ether transfer did not update token total supply");

		assert(String(await bankroll.balanceOf(accounts[0])) === String(100 * web3.toWei(11, "ether")), "ether transfer did not update user total supply");
	});

	it("should iterate over game contract functions and send them 5 ether", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		
		await bankroll.assessBankrollOfAllGames({from: accounts[0]});

		// games should both have 5 ether, and contract should have 1 ether
		assert(String(await bankroll.BANKROLL.call()) === String(web3.toWei(1, "ether")), "bankroll doesn't equal 1 ether after transfer");

		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		assert(String(await dice.BANKROLL.call()) === String(web3.toWei(5, "ether")), "transfer to dice didn't register");
		assert(String(await slots.BANKROLL.call()) === String(web3.toWei(5, "ether")), "transfer to slots didn't register");

		assert(String(await bankroll.getCurrentBalances()) === String(web3.toWei(11, "ether")), "getCurrentBalances didn't register");
	});

	it("should increase each game's target to 5.5 ether, and then send them it", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		await bankroll.changeTargetGameFunds(web3.toWei(5.5, "ether"), Dice.address, {from: accounts[0]});
		await bankroll.changeTargetGameFunds(web3.toWei(5.5, "ether"), Slots.address, {from: accounts[0]});

		assert(String(await bankroll.BANKROLL.call()) === String(web3.toWei(1, "ether")), "should be original balances, until calling assessBankrollOfAllGames");
		assert(String(await dice.BANKROLL.call()) === String(web3.toWei(5, "ether")), "...");
		assert(String(await slots.BANKROLL.call()) === String(web3.toWei(5, "ether")), "...");

		await bankroll.assessBankrollOfAllGames({from: accounts[0]});

		assert(String(await bankroll.BANKROLL.call()) === String(web3.toWei(0, "ether")), "should now have zero balance");
		assert(String(await dice.BANKROLL.call()) === String(web3.toWei(5.5, "ether")), "should now have 5.5 ether");
		assert(String(await slots.BANKROLL.call()) === String(web3.toWei(5.5, "ether")), "should now have 5.5 ether");
	});

	it("should decrease each game's target to 4 ether, and then take their ether", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		await bankroll.changeTargetGameFunds(web3.toWei(4, "ether"), Dice.address, {from: accounts[0]});
		await bankroll.changeTargetGameFunds(web3.toWei(4, "ether"), Slots.address, {from: accounts[0]});

		await bankroll.assessBankrollOfAllGames({from: accounts[0]});

		assert(String(await bankroll.BANKROLL.call()) === String(web3.toWei(3, "ether")), "should now have 1.5+1.5 = 3 ether");
		assert(String(await dice.BANKROLL.call()) === String(web3.toWei(4, "ether")), "should now have 4 ether");
		assert(String(await slots.BANKROLL.call()) === String(web3.toWei(4, "ether")), "should now have 4 ether");
	});

	it("should allow a 'cash out' of 100 tokens, burn the tokens, and send back 1 ether minus developers cut", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);

		var currentBalance = await web3.eth.getBalance(accounts[0]);

		await bankroll.cashoutINFSTokens((100 * web3.toWei(1, "ether")), {from: accounts[0]});

		assert(String(await bankroll.totalSupply.call()) === String(100 * web3.toWei(10, "ether")), "100 tokens were not burnt");
		assert(String(await bankroll.getCurrentBalances()) === String(web3.toWei(10, "ether")), "balance did not decrement");
		assert(String(await bankroll.DEVELOPERSFUND.call()) === String(web3.toWei(0.01, "ether")), "developers fund did not trigger");

		assert(String(await bankroll.balanceOf(accounts[0])) === String(100 * web3.toWei(10, "ether")), "did not decrement tokens from users balance");
		console.log('should be ~ 0.98 ether', web3.fromWei(await web3.eth.getBalance(accounts[0]) - currentBalance, "ether"));
		// assert(currentBalance + (web3.toWei(1, "ether") * 0.99) >= web3.eth.getBalance(accounts[0]) && currentBalance + (web3.toWei(1, "ether") * 0.98) <= web3.eth.getBalance(accounts[0]), "did not give user 1 ether minus 1% fee");
	});

	it("should allow a second user to lend 50 ether, and give him the correct tokens", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);
		
		await web3.eth.sendTransaction({to: InfinityBankroll.address, value: web3.toWei(50, "ether"), from: accounts[1]});

		// console.log('dice balance', await dice.BANKROLL.call());
		// console.log('slots balance', await slots.BANKROLL.call());
		// console.log('bankroll balance', await bankroll.BANKROLL.call());
		// console.log('current balances', await bankroll.getCurrentBalances());

		// check bankroll
		assert(String(await bankroll.totalSupply.call()) === String(100 * web3.toWei(60, "ether")), "should be 60.01 ether worth of tokens, token price still 100/ether");
		assert(String(await bankroll.getCurrentBalances()) === String(web3.toWei(60, "ether")), "should have 60 ether as total balances");

		// check user 2
		assert(String(await bankroll.balanceOf(accounts[1])) === String(100 * web3.toWei(50, "ether")), "user 2 did not get credited tokens");
	});

	it("should now raise dice + 46 ether -> 50 ether BANKROLL, and assessBalances of the games", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		await bankroll.changeTargetGameFunds(web3.toWei(50, "ether"), Dice.address, {from: accounts[0]});
		await bankroll.assessBankrollOfAllGames({from: accounts[0]});

		assert(String(await bankroll.BANKROLL.call()) === String(web3.toWei(6, "ether")), "should now have 6 ether");
		assert(String(await dice.BANKROLL.call()) === String(web3.toWei(50, "ether")), "should now have 50 ether");
		assert(String(await slots.BANKROLL.call()) === String(web3.toWei(4, "ether")), "should still have 4 ether");	
	});

	it("should now lose 1 ether playing dice, and assessBalances of the games", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		// play(uint256 betPerRoll, uint16 rolls, uint8 rollUnder)
		await dice.play(web3.toWei(0.5, "ether"), 500, 51, {from: accounts[2], value: web3.toWei(1, "ether")});

		// note, this is not a perfect test, if the player is really lucky he _could_ win, but if we test with the testrpc -d flag, it will pass (deterministic)
		// '50999999999999999998' -> 51 ether - 2 wei for the games that were lost. two wei is sent as a consolation prize for losses.
		// since there were two rolls made, the developer will get betPerRoll * houseEdgeInThousandthPercents * i / 10000
		// this is 0.5 ether * 2 rolls * 1% house edge * 10% developers cut = 1000000000000000
		// so then the bankroll will actually be 50999999999999999998 - 1000000000000000 = 50998999999999999998

		assert(String(await dice.DEVELOPERSFUND.call()) === '1000000000000000', "developers fund not correct");
		assert(String(await dice.BANKROLL.call()) === '50998999999999999998', "player should have lost 1 ether to the game");
	});

	it("player 1 cashing out 100 tokens should receive a little more than 1 ether because the total bankroll has gone up", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);

		// verify bankroll/tokens really quick...
		assert(String(await bankroll.getCurrentBalances()) === '60998999999999999998', "should have 61 ether as total balances, minus 2 wei, minus developers cut");
		assert(String(await bankroll.totalSupply.call()) === String(100 * web3.toWei(60, "ether")), "should be 15 ether worth of tokens, token price still 100/ether");

		await bankroll.cashoutINFSTokens((100 * web3.toWei(1, "ether")), {from: accounts[1]});

		// doing some math here...
		// tokens being cashed out == 100 tokens
		// total tokens == 6000 tokens
		// bankroll == 60998999999999999998
		// tokens cashed out ratio = 1/60
		// player should get back (1/60) * 60998999999999999998 wei
		// this equals 1016649999999999999 wei
		// developers percentage of withdrawal is 1% so 1016649999999999999 * 0.01 wei = 10166499999999999 wei + 0.01 ether from previous withdrawl
		// player then gets 1016666666666666666 * 0.99 wei = 1006483500000000000 wei
		// so the bankroll should be 60998999999999999998 - 1016649999999999999 = 59982349999999999999 wei

		assert(String(await bankroll.getCurrentBalances()) === '59982349999999999999', "total BANKROLL not correct");
		assert(String(await bankroll.DEVELOPERSFUND.call()) === '20166499999999999', 'DEVELOPERSFUND not correct');
	});

	it("should allow owner to withdraw the developers fund and credit account 1", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		// get developers funds from all contracts, add to account1 prior
		var balance = (await bankroll.DEVELOPERSFUND.call()).plus(await dice.DEVELOPERSFUND.call()).plus(await slots.DEVELOPERSFUND.call()).plus(await web3.eth.getBalance(accounts[1]));

		await bankroll.withdrawDevelopersFund(accounts[1], {from: accounts[0]});
		
		assert(String(balance) === String(await web3.eth.getBalance(accounts[1])), "withdrawing developers fund did not work correctly.");
	});

	it("should allow ERC20 token transfer from account[1] -> account[2]", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);

		var address1Tokens = await bankroll.balanceOf(accounts[1]);

		await bankroll.transfer(accounts[2], address1Tokens, {from: accounts[1]});

		assert(String(await bankroll.balanceOf(accounts[1])) === '0', 'address1 not drained of tokens');
		assert(String(await bankroll.balanceOf(accounts[2])) === String(address1Tokens), 'address2 not given tokens');
	});

	it("should allow account[2] to approve account 1 to withdraw every ERC20 token, and then account[1] withdraws every token", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);

		var address2Tokens = await bankroll.balanceOf(accounts[2]);

		await bankroll.approve(accounts[1], address2Tokens, {from: accounts[2]});
		await bankroll.transferFrom(accounts[2], accounts[1], address2Tokens, {from: accounts[1]});

		assert(String(await bankroll.balanceOf(accounts[1])) === String(address2Tokens), 'address1 not given tokens');
		assert(String(await bankroll.balanceOf(accounts[2])) === '0', 'address2 not drained of tokens');
	});


})