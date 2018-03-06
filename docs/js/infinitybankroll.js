// Thanks to @xavierlepretre for providing the basis of this function
// https://gist.github.com/xavierlepretre/88682e871f4ad07be4534ae560692ee6

// This allows you to poll for a transaction receipt being mined, and allows you to 
// circumvent the faulty metamask event watchers.
// In standard web3.js, a getTransactionReceipt returns null if the tx has not been
// mined yet. This will only return the actual receipt after the tx has been mined.

function getTransactionReceiptMined(txHash) {
    const self = this;
    const transactionReceiptAsync = function(resolve, reject) {
        web3.eth.getTransactionReceipt(txHash, (error, receipt) => {
            if (error) {
                reject(error);
            } else if (receipt == null) {
                setTimeout(
                    () => transactionReceiptAsync(resolve, reject), 500);
            } else {
                resolve(receipt);
            }
        });
    }
    return new Promise(transactionReceiptAsync);
};

async function getStaticValueFromBankroll(BankrollValue){
    return new Promise ( (resolve, reject) => {
        BankrollValue( (error, result) => {
            if (error){
                reject(error);
            }
            else {
                resolve(new BigNumber(result));
            }
        });
    });     
};

async function getStaticMappingFromBankroll(BankrollMapping, MappingId){
    return new Promise ( (resolve, reject) => {
        BankrollMapping(MappingId, (error, result) => {
            if (error){
                reject(error);
            }
            else {
                resolve(new BigNumber(result));
            }
        });
    });     
};

InfinityBankroll = {
    web3Provider: null,
    Bankroll: null,
    bankrollInstance: null,
    /// contract data
    currentTotalBankrollBalance: null,
    currentTotalTokenSupply: null,
    currentUserTokenSupply: null,
    currentUserTokenValue: null,
    maxWithdrawTokens: null,
    maximumBankrollContributions: null,
    currentContractBankrollBalance: null,


    init: function() {
        InfinityBankroll.initWeb3();
        InfinityBankroll.bindInitialEvents();
    },

    initWeb3: function() {
        setTimeout(function(){
            if (typeof web3 !== 'undefined'){
                console.log('getting web3');
                InfinityBankroll.web3Provider = web3.currentProvider;

                web3.version.getNetwork( (error, result) => {
                    if (error || result !== '4'){
                        launchWrongNetworkModal('Infinity Bankroll');
                        return;
                    }
                    else {
                        return InfinityBankroll.initContract(web3);
                    }
                });
            }
            else {
                launchNoMetaMaskModal('Infinity Bankroll');
                return;
            }
        }, 500);
    },

    initContract: function(web3){
        $.getJSON('./abi/BankrollABI.json', function(data){
            // get contract ABI and init
            var bankrollAbi = data;
            // rinkeby: 0x6ce0f38DB787434f2ED0C7DE8C61be2FAAe87f32
            InfinityBankroll.Bankroll = web3.eth.contract(bankrollAbi);
            InfinityBankroll.bankrollInstance = InfinityBankroll.Bankroll.at('0xD93ae87409D6CCceB2612dA9c2a832829F6A17A4');

            return InfinityBankroll.getUserDetails(web3);

        });
    },

    bindInitialEvents: function(){
        $('#withdraw').click(function() {InfinityBankroll.withdraw(false); });
        $('#deposit').click(function() {InfinityBankroll.deposit(); });
        $('#withdraw-all').click(function(){InfinityBankroll.withdraw(true); });
    },

    getUserDetails: function(web3){
        var accounts = web3.eth.accounts;
        if (accounts.length === 0){
            launchNoLoginModal('Infinity Bankroll');
        }

        return InfinityBankroll.getContractDetails(web3);
    },

    getContractDetails: async function(web3){
        // first get the withdrawl details
        try {
            InfinityBankroll.currentTotalBankrollBalance = await getStaticValueFromBankroll(InfinityBankroll.bankrollInstance.getBankroll);
            InfinityBankroll.currentTotalTokenSupply = await getStaticValueFromBankroll(InfinityBankroll.bankrollInstance.totalSupply);
            InfinityBankroll.currentUserTokenSupply = await getStaticMappingFromBankroll(InfinityBankroll.bankrollInstance.balanceOf, web3.eth.accounts[0]);
            // calculate value of tokens given these values
            InfinityBankroll.currentUserTokenValue = InfinityBankroll.currentTotalBankrollBalance.times(InfinityBankroll.currentUserTokenSupply).dividedBy(InfinityBankroll.currentTotalTokenSupply);

            $('#current-tokens').text(web3.fromWei(InfinityBankroll.currentUserTokenSupply, "ether"));
            $('#current-tokens-value').text(isNaN(InfinityBankroll.currentUserTokenValue) ? 0 : web3.fromWei(InfinityBankroll.currentUserTokenValue, "ether"));

            if (InfinityBankroll.currentUserTokenSupply.greaterThan(0)){
                var mandatoryWaitTime = parseInt(await getStaticValueFromBankroll(InfinityBankroll.bankrollInstance.WAITTIMEUNTILWITHDRAWORTRANSFER), 10);
                var usersContributionTime = parseInt(await getStaticMappingFromBankroll(InfinityBankroll.bankrollInstance.checkWhenContributorCanTransferOrWithdraw, web3.eth.accounts[0]), 10);
                
                var thisTime = Math.floor(Date.now() / 1000);

                // if the user can withdraw their tokens, then get details about the withdraw
                if (usersContributionTime + mandatoryWaitTime >= thisTime){
                    var remainingWaitTime = mandatoryWaitTime - (thisTime - usersContributionTime);

                    var inWeeks = Math.floor(remainingWaitTime / 604800);
                    var inDays = Math.floor((remainingWaitTime - (inWeeks * 604800)) / 86400);
                    var inHours = Math.floor((remainingWaitTime - (inWeeks * 604800) - (inDays * 86400)) / 3600);
                    var inMinutes = Math.floor((remainingWaitTime - (inWeeks * 604800) - (inDays * 86400) - (inHours * 3600)) / 60);

                    $('#withdraw-info').show();
                    $('#withdraw-info').html('You must wait ');

                    if (inWeeks > 0){
                        $('#withdrawal-info').append(inWeeks.toString() + ' weeks ');
                    }
                    if (inDays > 0){
                        $('#withdraw-info').append(inDays.toString() + ' days ');
                    }
                    if (inHours > 0){
                        $('#withdraw-info').append(inHours.toString() + ' hours and ');
                    }
                    $('#withdraw-info').append(inMinutes.toString() + ' minutes until you may cash in your tokens for ether, or transfer your tokens to a different account.');
                }   
            }

            // now get the deposit details
            InfinityBankroll.maximumBankrollContributions = await getStaticValueFromBankroll(InfinityBankroll.bankrollInstance.MAXIMUMINVESTMENTSALLOWED);
            // determine how much the user can contribute
            var youCanContribute;
            if (InfinityBankroll.maximumBankrollContributions.lessThan(InfinityBankroll.currentTotalBankrollBalance)){
                youCanContribute = 0;
            }
            else {
                youCanContribute = InfinityBankroll.maximumBankrollContributions.minus(InfinityBankroll.currentTotalBankrollBalance);
            }
            // update the UI with this info
            $('#current-ether').text(web3.fromWei(InfinityBankroll.currentTotalBankrollBalance, "ether"));
            $('#contributable-ether').text(web3.fromWei(youCanContribute, "ether"));
            $('#ether-cap').text(web3.fromWei(InfinityBankroll.maximumBankrollContributions, "ether"));

            $('#deposit-info').show();
            $('#deposit-info').html("MAX: " + web3.fromWei(youCanContribute, "ether") + " ether.");

        } catch(error) {
            console.log('Error while determining withdraw/deposit details', error); 
        }
    },

    deposit: function(){
        var depositAmt = $('#deposit-amt').val();

        web3.eth.sendTransaction({to: InfinityBankroll.bankrollInstance.address, from: web3.eth.accounts[0], value: web3.toWei(depositAmt, "ether")}, async function(error, result){
            if (error){
                console.log('error while depositing ether to fallback', error);
            }
            else {
                $('#deposit-info').html('Waiting for deposit to be processed... one moment please');

                var txHash = result;
                var txReceipt = await getTransactionReceiptMined(txHash);

                if (txReceipt.logs.length === 0){
                    $('#deposit-info').removeClass("alert-default").addClass("alert-danger");
                    $('#deposit-info').html('Uh oh, your deposit seemed to fail! Please check your account on etherscan for more info...');
                }
                else if (txReceipt.logs.length === 1){

                    var data = txReceipt.logs[0]['data'];

                    var amountEther = parseInt(data.slice(66, 130), 16).toString();
                    var amountTokens = parseInt(data.slice(130, 194), 16).toString();
                    $('#deposit-info').removeClass("alert-default").addClass("alert-success");
                    $('#deposit-info').html('You have successfully deposited ' + web3.fromWei(amountEther, "ether") + ' ether to our bankroll and have been given ' + web3.fromWei(amountTokens, "ether") + ' INFS Tokens! Thank you for contributing to INFINITY BANKROLL.');
                }
            }
        });
    },

    withdraw: function(all){
        if (all === true){
            // withdraw all tokens, use smart contract function cashoutINFSTokens_ALL
            InfinityBankroll.bankrollInstance.cashoutINFSTokens_ALL({from: web3.eth.accounts[0]}, async function(error, result){
                if (error){
                    console.log('error while withdrawing all INFS tokens', error);
                }
                else {
                    await InfinityBankroll.parseWithdrawLogs(result);
                }
            });
        }
        else {
            // only withdraw some tokens
            var withdrawAmt = $('#withdraw-amt').val();

            InfinityBankroll.bankrollInstance.cashoutINFSTokens(web3.toWei(withdrawAmt, "ether"), {from: web3.eth.accounts[0]}, async function(error, result){
                if (error){
                    console.log('error while withdrawing INFS tokens', error);
                }
                else {
                    await InfinityBankroll.parseWithdrawLogs(result);
                }
            });
        }
    },

    parseWithdrawLogs: async function(txHash){
        $('#withdraw-info').show();
        $('#withdraw-info').html('Waiting for withdrawal to be processed... one moment please');

        var txReceipt = await getTransactionReceiptMined(txHash);

        if (txReceipt.logs.length === 0){
            $('#withdraw-info').html('Uh oh, your withdrawal seemed to fail! Please check your account on etherscan for more info...');
        }
        else {

             var data = txReceipt.logs[0]['data'];

            var amountEther = parseInt(data.slice(66, 130), 16).toString();
            var amountTokens = parseInt(data.slice(130, 194), 16).toString();

            $('#withdraw-info').html('You successfully cashed in ' + web3.fromWei(amountTokens, "ether") + ' INFS tokens and have been sent ' + web3.fromWei(amountEther, "ether") + ' ether. Thank you for contributing to our bankroll!');
        }
    }
    
}

$(document).ready(function(){
    InfinityBankroll.init();
});

