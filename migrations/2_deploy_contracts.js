var Dice = artifacts.require("./InfinityDice.sol");
var Slots = artifacts.require("./MoonMissionSlots.sol");
var InfinityBankroll = artifacts.require("./InfinityBankroll.sol");

module.exports = function(deployer, network, accounts) {
	if (network == 'development'){

		deployer.then(function(){
			return deployer.deploy(Dice, false, 0, 0, 0);
		}).then(function(){
			return deployer.deploy(Slots, false, 0, 0, 0);
		}).then(function(){
			return deployer.deploy(InfinityBankroll, Slots.address, Dice.address, {from: accounts[0], value:web3.toWei(11, "ether")});
		}).then(function(){
			return Dice.at(Dice.address).setBankrollerContractOnce(InfinityBankroll.address, {from: accounts[0]});
		}).then(function(){
			return Slots.at(Slots.address).setBankrollerContractOnce(InfinityBankroll.address, {from: accounts[0]});
		});
	}
};
