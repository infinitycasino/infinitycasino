var InfinityBankroll = artifacts.require("InfinityBankroll");
var Dice = artifacts.require("InfinityDice");
var Slots = artifacts.require("MoonMissionSlots");
// grab bignumber from the website src
const BigNumber = require('../src/js/bignumber.min.js');

contract("Test_InfinityBankroll_IntegrationTest", function(accounts){

	it("should deploy bankroll & send 11 ether, and update ether/token balances", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);

		assert(String(await bankroll.BANKROLL.call()) === String(web3.toWei(11, "ether")), "ether transfer did not register");
		assert(String(await bankroll.totalSupply.call()) === String(100 * web3.toWei(11, "ether")), "ether transfer did not update token total supply");

		assert(String(await bankroll.balanceOf(accounts[0])) === String(100 * web3.toWei(11, "ether")), "ether transfer did not update user total supply");
	});

	it("should iterate over game contract functions and send them 5 ether", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		
		await bankroll.assessBankrollOfAllGames({from: accounts[0], gasPrice: 0});

		// games should both have 5 ether, and contract should have 1 ether
		assert(String(await bankroll.BANKROLL.call()) === String(web3.toWei(1, "ether")), "bankroll doesn't equal 1 ether after transfer");

		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		assert(String(await dice.BANKROLL.call()) === String(web3.toWei(5, "ether")), "transfer to dice didn't register");
		assert(String(await slots.BANKROLL.call()) === String(web3.toWei(5, "ether")), "transfer to slots didn't register");

		assert(String(await bankroll.getCurrentBalances()) === String(web3.toWei(11, "ether")), "getCurrentBalances didn't register");
	});

	it("should increase each game's target to 5.5 ether, and then send them it", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		await bankroll.changeTargetGameFunds(web3.toWei(5.5, "ether"), Dice.address, {from: accounts[0], gasPrice: 0});
		await bankroll.changeTargetGameFunds(web3.toWei(5.5, "ether"), Slots.address, {from: accounts[0], gasPrice: 0});

		assert(String(await bankroll.BANKROLL.call()) === String(web3.toWei(1, "ether")), "should be original balances, until calling assessBankrollOfAllGames");
		assert(String(await dice.BANKROLL.call()) === String(web3.toWei(5, "ether")), "...");
		assert(String(await slots.BANKROLL.call()) === String(web3.toWei(5, "ether")), "...");

		await bankroll.assessBankrollOfAllGames({from: accounts[0]});

		assert(String(await bankroll.BANKROLL.call()) === String(web3.toWei(0, "ether")), "should now have zero balance");
		assert(String(await dice.BANKROLL.call()) === String(web3.toWei(5.5, "ether")), "should now have 5.5 ether");
		assert(String(await slots.BANKROLL.call()) === String(web3.toWei(5.5, "ether")), "should now have 5.5 ether");
	});

	it("should decrease each game's target to 4 ether, and then take their ether", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		await bankroll.changeTargetGameFunds(web3.toWei(4, "ether"), Dice.address, {from: accounts[0], gasPrice: 0});
		await bankroll.changeTargetGameFunds(web3.toWei(4, "ether"), Slots.address, {from: accounts[0], gasPrice: 0});

		await bankroll.assessBankrollOfAllGames({from: accounts[0], gasPrice: 0});

		assert(String(await bankroll.BANKROLL.call()) === String(web3.toWei(3, "ether")), "should now have 1.5+1.5 = 3 ether");
		assert(String(await dice.BANKROLL.call()) === String(web3.toWei(4, "ether")), "should now have 4 ether");
		assert(String(await slots.BANKROLL.call()) === String(web3.toWei(4, "ether")), "should now have 4 ether");
	});

	it("should allow a 'cash out' of 100 tokens, burn the tokens, and send back 1 ether minus developers cut", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);

		var originalBalance = await web3.eth.getBalance(accounts[0]);

		await bankroll.cashoutINFSTokens((100 * web3.toWei(1, "ether")), {from: accounts[0], gasPrice: 0});

		assert(String(await bankroll.totalSupply.call()) === String(100 * web3.toWei(10, "ether")), "100 tokens were not burnt");
		assert(String(await bankroll.getCurrentBalances()) === String(web3.toWei(10, "ether")), "balance did not decrement");
		assert(String(await bankroll.DEVELOPERSFUND.call()) === String(web3.toWei(0.01, "ether")), "developers fund did not trigger");

		assert(String(await bankroll.balanceOf(accounts[0])) === String(100 * web3.toWei(10, "ether")), "did not decrement tokens from users balance");
		// note, gasPrice is set to zero in all functions, so we don't have to account for it in asserts like these
		// make sure to keep gas price at zero for subsequent calls, so these always work
		assert(String(originalBalance) === String((await web3.eth.getBalance(accounts[0])).minus(new BigNumber(web3.toWei(0.99, "ether"))) ), "did not give user 1 ether minus 1% fee");
	});

	it('should allow owner to raise the maximum contributions to 50 ether', async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);

		await bankroll.changeMaximumInvestmentsAllowed(web3.toWei(50, "ether"), {from: accounts[0], gasPrice: 0});

		assert(String(await bankroll.MAXIMUMINVESTMENTSALLOWED.call()) === String(web3.toWei(50, "ether")), "did not change maximum investments allowed");
	})

	it("should allow a second user to lend 20 ether, and give him the correct tokens", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		
		await web3.eth.sendTransaction({to: InfinityBankroll.address, value: web3.toWei(20, "ether"), from: accounts[1], gasPrice: 0});

		// check bankroll
		assert(String(await bankroll.totalSupply.call()) === String(100 * web3.toWei(30, "ether")), "should be 30 ether worth of tokens, token price still 100/ether");
		assert(String(await bankroll.getCurrentBalances()) === String(web3.toWei(30, "ether")), "should have 30 ether as total balances");

		// check user 2
		assert(String(await bankroll.balanceOf(accounts[1])) === String(100 * web3.toWei(20, "ether")), "user 2 did not get credited tokens");
	});

	it("should allow a third user to lend 30 ether, but only give him 20 ether worth of tokens and refund 10 ether", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var user2BalanceOriginal = web3.eth.getBalance(accounts[2]);

		await web3.eth.sendTransaction({to: InfinityBankroll.address, value: web3.toWei(30, "ether"), from: accounts[2], gasPrice: 0});

		// check bankroll
		assert(String(await bankroll.totalSupply.call()) === String(100 * web3.toWei(50, "ether")), "should be 50 ether worth of tokens, token price still 100/ether");
		assert(String(await bankroll.getCurrentBalances()) === String(web3.toWei(50, "ether")), "should have 50 ether as total balances");

		//check user 3
		assert(String(await bankroll.balanceOf(accounts[2])) === String(100 * web3.toWei(20, "ether")), "user 3 did not get credited tokens");
		assert(String(await web3.eth.getBalance(accounts[2])) === String(user2BalanceOriginal.minus(new BigNumber(web3.toWei(20, "ether")))), 'user 3 balance is incorrect, should be -20 eth');
	});

	it("has 50 ether total, assign 45 ether to dice and keep slots at 4 ether & bankroll at 1 ether", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		await bankroll.changeTargetGameFunds(web3.toWei(45, "ether"), Dice.address, {from: accounts[0], gasPrice: 0});
		await bankroll.assessBankrollOfAllGames({from: accounts[0], gasPrice: 0});

		assert(String(await bankroll.BANKROLL.call()) === String(web3.toWei(1, "ether")), "should now have 1 ether");
		assert(String(await dice.BANKROLL.call()) === String(web3.toWei(45, "ether")), "should now have 50 ether");
		assert(String(await slots.BANKROLL.call()) === String(web3.toWei(4, "ether")), "should still have 4 ether");	
	});


	it("should now lose 1 ether playing dice, and assessBalances of the games", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		await dice.play(web3.toWei(1, "ether"), 1, 12, {from: accounts[2], value: web3.toWei(1, "ether"), gasPrice: 0});

		// note, this is not a perfect test, if the player is really lucky he _could_ win, but if we test with the testrpc -d flag, it will pass (deterministic)
		// '45998999999999999999' -> 46 ether - 2 wei for the games that were lost. two wei is sent as a consolation prize for losses.
		// since there were two rolls made, the developer will get betPerRoll * houseEdgeInThousandthPercents * i / 10000
		// so then the bankroll will actually be 50999999999999999998 - 1000000000000000 = 50998999999999999998

		assert((await dice.DEVELOPERSFUND.call()).toString() === '1000000000000000', "developers fund not correct");
		assert((await dice.BANKROLL.call()).toString() === '45998999999999999999', "player should have lost 1 ether to the game");

		// now run assess balances
		await bankroll.assessBankrollOfAllGames({from: accounts[0], gasPrice: 0});

		// games should go back to their original balances of 45 eth for dice, and 4 eth for slots

		assert((await dice.BANKROLL.call()).toString() === web3.toWei(45, "ether").toString(), "dice is not at 45 ether balance");
		assert((await slots.BANKROLL.call()).toString() === web3.toWei(4, "ether").toString(), "slots is not at 4 ether balance");

		assert((await bankroll.BANKROLL.call()).toString() === '1998999999999999999', "bankroll does not have correct balance after running assess");
	});

	it("player 1 cashing out 50 tokens should receive a little more than 1 ether because the total bankroll has gone up", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);

		var originalBalance = await web3.eth.getBalance(accounts[1]);

		// verify bankroll/tokens really quick...
		assert(String(await bankroll.getCurrentBalances()) === '50998999999999999999', "should have 51 ether as total balances, minus 2 wei, minus developers cut");
		assert(String(await bankroll.totalSupply.call()) === String(100 * web3.toWei(50, "ether")), "should be 50 ether worth of tokens, token price still 100/ether");

		await bankroll.cashoutINFSTokens(100 * web3.toWei(1, "ether"), {from: accounts[1], gasPrice: 0});

		// doing some math here...
		// tokens being cashed out == 100 tokens
		// total tokens == 5000 tokens
		// bankroll == 50998999999999999999
		// tokens cashed out ratio = 1/50
		// player should get back (1/50) * 50998999999999999999 wei
		// this equals 1019979999999999999 wei, but we need to subtract the developers cut amount.
		// developers percentage of withdrawal is 1% so 1019979999999999999 * 0.01 = 10199799999999999 wei + 0.01 ether from previous withdrawl
		// player then gets 1019979999999999999 - 10199799999999999 = 1009780200000000000 wei
		// so the bankroll should be 50998999999999999999 - 1019979999999999999 = 49979020000000000000 wei

		assert(String(await bankroll.getCurrentBalances()) === '49979020000000000000', "total BANKROLL not correct");
		assert(String(await bankroll.DEVELOPERSFUND.call()) === '20199799999999999', 'DEVELOPERSFUND not correct');

		assert(originalBalance.plus(new BigNumber('1009780200000000000')).toString() === (await web3.eth.getBalance(accounts[1])).toString() );
	});

	it("should allow owner to withdraw the developers fund and credit account 8", async function(){
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		var originalBalance = await web3.eth.getBalance(accounts[8])

		// get developers funds from all contracts, add to account1 prior
		var balance = (await bankroll.DEVELOPERSFUND.call()).plus(await dice.DEVELOPERSFUND.call()).plus(await slots.DEVELOPERSFUND.call()).plus(originalBalance).toString();

		await bankroll.withdrawDevelopersFund(accounts[8], {from: accounts[0], gasPrice: 0});
		
		assert(balance.toString() === (await web3.eth.getBalance(accounts[8])).toString(), "withdrawing developers fund did not work correctly.");
	});

	it("should allow ERC20 token transfer from account[1] -> account[8]", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);

		var address1Tokens = await bankroll.balanceOf(accounts[1]);

		await bankroll.transfer(accounts[8], address1Tokens, {from: accounts[1], gasPrice: 0});

		assert(String(await bankroll.balanceOf(accounts[1])) === '0', 'address1 not drained of tokens');
		assert(String(await bankroll.balanceOf(accounts[8])) === String(address1Tokens), 'address2 not given tokens');
	});

	it("should allow account[8] to approve account[1] to withdraw every ERC20 token, and then account[1] withdraws every token", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);

		var address8Tokens = await bankroll.balanceOf(accounts[8]);

		await bankroll.approve(accounts[1], address8Tokens, {from: accounts[8], gasPrice: 0});
		await bankroll.transferFrom(accounts[8], accounts[1], address8Tokens, {from: accounts[1], gasPrice: 0});

		assert(String(await bankroll.balanceOf(accounts[1])) === String(address8Tokens), 'address1 not given tokens');
		assert(String(await bankroll.balanceOf(accounts[8])) === '0', 'address8 not drained of tokens');
	});

	it('should transfer ownership to account[8]', async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		await bankroll.transferOwnership(accounts[8], {from: accounts[0], gasPrice: 0});
		await dice.transferOwnership(accounts[8], {from: accounts[0], gasPrice: 0});
		await slots.transferOwnership(accounts[8], {from: accounts[0], gasPrice: 0});

		assert(await bankroll.OWNER.call() === accounts[8], 'ownership was not transferred of bankroll');
		assert(await dice.OWNER.call() === accounts[8], 'ownership was not transferred of dice');
		assert(await slots.OWNER.call() === accounts[8], 'ownership was not transferred of slots');
	});

	it("should change dice to 4 eth, and slots to 45 eth, and bankroll should remain at previous value", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var dice = await Dice.at(Dice.address);
		var slots = await Slots.at(Slots.address);

		await bankroll.changeTargetGameFunds(web3.toWei(4, "ether"), Dice.address, {from: accounts[8], gasPrice: 0});
		await bankroll.assessBankrollOfAllGames({from: accounts[8], gasPrice: 0});

		// now dice & slots should be at 4 ether, and bankroll should have the remaining ether.
		assert((await dice.BANKROLL.call()).toString() === web3.toWei(4, "ether").toString(), "dice is not at 4 ether balance");
		assert((await slots.BANKROLL.call()).toString() === web3.toWei(4, "ether").toString(), "slots is not at 4 ether balance");
		assert((await bankroll.BANKROLL.call()).toString() === '41979020000000000000', "bankroll does not have correct balance after running assess");

		await bankroll.changeTargetGameFunds(web3.toWei(45, "ether"), Slots.address, {from: accounts[8], gasPrice: 0});
		await bankroll.assessBankrollOfAllGames({from: accounts[8], gasPrice: 0});

		// now dice & slots should be at 4 ether, and bankroll should have the remaining ether.
		assert((await dice.BANKROLL.call()).toString() === web3.toWei(4, "ether").toString(), "dice is not at 4 ether balance");
		assert((await slots.BANKROLL.call()).toString() === web3.toWei(45, "ether").toString(), "slots is not at 45 ether balance");
		assert((await bankroll.BANKROLL.call()).toString() === '979020000000000000', "bankroll does not have correct balance after running assess");
	});

	it("should lose one spin of slots at 0.001 ether, and update developers cut and bankroll accordingly", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var slots = await Slots.at(Slots.address);

		await slots.play(1, {value: web3.toWei(0.001, "ether"), from: accounts[7], gasPrice: 0});

		// 0.01 ether going into slots, 5% house edge, and 20% of that to developers
		var contributionAmt = new BigNumber(web3.toWei(0.001, "ether"));
		var developersFund = contributionAmt.dividedBy(20).dividedBy(5);

		assert((await slots.DEVELOPERSFUND.call()).toString() === developersFund.toString(), "developers fund not correct");
		assert((await slots.BANKROLL.call()).toString() === (new BigNumber(web3.toWei(45, "ether"))).plus(contributionAmt).minus(developersFund).toString(), "bankroll not correct");
	});

	it("should send this new developers fund to accounts[7]", async () => {
		var bankroll = await InfinityBankroll.at(InfinityBankroll.address);
		var slots = await Slots.at(Slots.address);

		var originalBalance = await web3.eth.getBalance(accounts[7]);
		var developersBalance = await slots.DEVELOPERSFUND.call();

		await bankroll.withdrawDevelopersFund(accounts[7], {from: accounts[8], gasPrice: 0});

		assert(originalBalance.plus(developersBalance).toString() === (await web3.eth.getBalance(accounts[7])).toString());
	});
})