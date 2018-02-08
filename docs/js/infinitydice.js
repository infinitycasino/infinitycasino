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

function hexToBinary(hexString){
    var hexAlphabet = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];
    var binaryAlphabet = ['0000', '0001', '0010', '0011', '0100', '0101', '0110', '0111', '1000', '1001', '1010', '1011', '1100', '1101', '1110', '1111'];

    var binaryString = '';
    var hexChar;
    var binaryChar;
    for (var i = 0; i < hexString.length; i++){
        hexChar = hexString.charAt(i);
        binaryChar = binaryAlphabet[hexAlphabet.indexOf(hexChar)];

        binaryString += binaryChar;
    }

    return binaryString;
}

InfinityDice = {
    // START CONTRACT DATA
    maxRolls: 1024, // this is hard coded into the contract.
    maxWinPerSpin: null, 
    minBet: null,
    houseEdge: 10,
    player: null, // players ethereum address.
    playerBalance: null, // players balance in wei
    // data when credits are purchased.
    betPerRoll: null,
    totalRolls: null,
    rollUnder: null,
    totalBet: null,
    currentProfit: null,
    // data when credits are given by oraclize
    onRoll: null,
    rollData: null,
    // web3 stuff
    web3Provider: null,
    Dice: null,
    diceInstance: null,

    init: function() {
        InfinityDice.initWeb3();
        InfinityDice.bindInitialEvents();
    },

    initWeb3: function() {
        setTimeout(function(){
            if (typeof web3 !== 'undefined'){
                console.log('getting web3');
                InfinityDice.web3Provider = web3.currentProvider;
            }
            else {
                launchNoMetaMaskModal('Infinity Dice');
            }

            return InfinityDice.initContract(web3);

        }, 500);
    },

    initContract: function(web3){
        $.getJSON('./abi/DiceABI.json', function(data){
            // get contract ABI and init
            var diceAbi = data;
            
            InfinityDice.Dice = web3.eth.contract(diceAbi);
            InfinityDice.diceInstance = InfinityDice.Dice.at('0xec8e1042C9eC9386c75F79368697cd51c5731469');

            return InfinityDice.getContractDetails(web3);

        });
    },

    getContractDetails: function(web3){
        var amountWagered = InfinityDice.diceInstance.AMOUNTWAGERED.call(function(error, result){
            if (error){
                console.log('could not retreive balance!');
            }
            else {
                $('#amt-wagered').html(web3.fromWei(result, "ether").toString().slice(0,7));
            }
        });
        var gamesPlayed = InfinityDice.diceInstance.GAMESPLAYED.call(function(error, result){
            if (error){
                console.log('could not get games played');
            }
            else {
                $('#games-played').html(result.toString());
            }
        });
        var maxWinPerSpin = InfinityDice.diceInstance.MAXWIN_inTHOUSANDTHPERCENTS.call(function(error, result){
            if (error){
                console.log('could not get bet limit');
            }
            else {
                var maxWin = result;

                InfinityDice.diceInstance.BANKROLL.call(function(error, result){
                    if (error){
                        console.log('could not get bankroll!');
                    }
                    else {
                        var max = new BigNumber(result.times(maxWin).dividedBy(1000).toFixed(0));
                        $('#max-win').html(web3.fromWei(max, "ether").toString().slice(0,7));
                        InfinityDice.maxWinPerSpin = max;
                    }
                });
            }
        });
        var minBetPerSpin = InfinityDice.diceInstance.MINBET.call(function(error, result){
            if (error){
                console.log('could not get min bet');
            }
            else {
                InfinityDice.minBet = result;
                $('#min-bet').text(web3.fromWei(result, "ether").toString().slice(0,7));
            }
        })
        var houseEdge = InfinityDice.diceInstance.HOUSEEDGE_inTHOUSANDTHPERCENTS.call(function(error, result){
            if (error){
                console.log('could not get game paused');
            }
            else {
                InfinityDice.houseEdge = new BigNumber(result.dividedBy(10));
            }
        });
        var gamePaused = InfinityDice.diceInstance.GAMEPAUSED.call(function(error, result){
            if (error){
                console.log('could not get game paused');
            }
            else {
                if (result === true){
                    alert('Game is paused! No bets please!');
                }
            }
        });
        
        return InfinityDice.getPlayerDetails(web3);
    },

    getPlayerDetails: function(web3){
        var accounts = web3.eth.accounts;
        if (accounts.length === 0){
            launchNoLoginModal('Infinity Dice');
        }
        else {
            var playersAccount = accounts[0];
            $('#players-address').html(String(playersAccount));

            var playersBalance = web3.eth.getBalance(playersAccount, function(error, result){
                if (error) {
                    console.log('could not get players balance');
                }
                else {
                    $('#players-balance').html(web3.fromWei(result, "ether").toString());
                    InfinityDice.playerBalance = result;
                }
            });
            InfinityDice.player = playersAccount;
        }
    },

    bindInitialEvents: function() {
        $('#buy-rolls').click(function() {InfinityDice.buyRolls(); });
        $('#roll-dice').click(function() {InfinityDice.rollDice(); });
    },

    buyRolls: function(){
        // from sliders
        InfinityDice.rollUnder = rollUnderValue();
        InfinityDice.totalRolls = numberRollsValue();
        // amount bet
        InfinityDice.betPerRoll = new BigNumber(web3.toWei($('#bet-per-roll').val(), "ether"));
        // total amt to send
        InfinityDice.totalBet = new BigNumber(InfinityDice.betPerRoll.times(guaranteedRollsValue()).toFixed(0));

        InfinityDice.onRoll = 0;

        player = InfinityDice.getPlayerDetails(web3);
        
        InfinityDice.diceInstance.play(InfinityDice.betPerRoll.toString(), InfinityDice.totalRolls.toString(), InfinityDice.rollUnder.toString(), {value: InfinityDice.totalBet.toString(), from: player}, async function(error, result){
            if (error){
                console.log('error while purchasing rolls ---', error);
            }
            else {
                $('#game-info').show();
                $('#game-info').html('transaction waiting to be mined');
                var txHash = result;
                var txReceipt = await getTransactionReceiptMined(txHash);

                // now parse the logs to determine if the transaction was already resolved, or was sent to oraclize
                // for miner-proof randomness...
                if (txReceipt.logs.length === 0){
                    $('#game-info').removeClass("alert-info").addClass("alert-danger");
                    $('#game-info').html('UH OH! Transaction seemed to fail! Please try again or check etherscan for more info...');
                }
                // if there is a single log, then the transaction was resolved internally.
                // now we just need to parse the game data and play some dice!
                else if (txReceipt.logs.length === 1){

                    var data = txReceipt.logs[0]['data'];

                    console.log('all data', data);

                    InfinityDice.parseRolls(data);
                }
                // if there was two logs, then the bettor bet enough for the call to get forwarded to oraclize
                // get the oraclize query id, and then watch for an event with this id.
                else if (txReceipt.logs.length === 2){
                    $('#game-info').removeClass("alert-info").addClass("alert-success");
                    $('#game-info').html('Transaction mined! Please wait, fetching provable randomness from our provider...');

                    var resultTopic = '0xb9d44d01b9e36e98413c2ed40b61f560e40595343f3cc734c988da4db5dd6563';
                    var ledgerProofFailTopic = '0x2576aa524eff2f518901d6458ad267a59debacb7bf8700998dba20313f17dce6';
                    var oraclizeQueryId = txReceipt.logs[1]['topics'][1];

                    var watchForResult = web3.eth.filter({topics:[resultTopic, oraclizeQueryId], fromBlock: 'pending', to: InfinityDice.diceInstance.address});
                    var watchForFail = web3.eth.filter({topics:[ledgerProofFailTopic, oraclizeQueryId], fromBlock: 'pending', to: InfinityDice.diceInstance.address});

                    watchForResult.watch(function(error, result){
                        if (error){
                            console.log('error while fetching result event', error);
                        }
                        else {

                            watchForResult.stopWatching();
                            watchForFail.stopWatching();

                            var data = result.data;

                            InfinityDice.parseRolls(data);
                        }
                    });

                    watchForFail.watch(function(error, result){
                        if (error){
                            console.log('ledger proof failed, but error', error);
                        }
                        else {
                            watchForResult.stopWatching();
                            watchForFail.stopWatching();
                            $('#game-info').removeClass("alert-success").addClass("alert-danger");
                            $('#game-info').html('We apologize, but the random number has not passed our test of provable randomness, so all your ether has been refunded. Please feel free to play again, or read more about our instantly provable randomness generation here (((((LINK HERE)))))). We strive to bring the best online gambling experience at Infinity Casino, and occasionally the random numbers generated do not pass our stringent testing.');
                        }
                    });
                }
            }
        });
    },

    parseRolls: function(data){
        // NOTE: fade out roll selection screen, fade in the roll screen
        $('#game-info').hide();
        $('#roll-dice').show();

        InfinityDice.currentProfit = InfinityDice.totalBet;

        rollsReady(InfinityDice.betPerRoll, InfinityDice.totalBet, InfinityDice.totalRolls, InfinityDice.rollUnder);

        // get the amount of rolls that actually happened from the logs
        var rolls = parseInt(data.slice(2, 66), 16);

        // get the roll data (in a hex string, convert to binary)..
        // then we need to slice this string again, because after the rolls are done, it will all be 00000000
        InfinityDice.rollData = hexToBinary(data.slice(66, 322)).slice(0, rolls);
    },

    rollDice: async function(){
        var win = InfinityDice.rollData.charAt(InfinityDice.onRoll) === '1';

        var houseEdgeMult = ((100 - InfinityDice.houseEdge) / 100).toString();
        var profitMult = (100 / (InfinityDice.rollUnder - 1)).toString();

        var winSize = InfinityDice.betPerRoll.times(profitMult).times(houseEdgeMult).minus(InfinityDice.betPerRoll);
        console.log('win size', winSize);

        // increment or decrement current profit based on win or not
        win ? InfinityDice.currentProfit = InfinityDice.currentProfit.add(winSize) : InfinityDice.currentProfit = InfinityDice.currentProfit.minus(InfinityDice.betPerRoll);
        console.log(InfinityDice.currentProfit);
        await rollingDice(win, InfinityDice.rollUnder, winSize, InfinityDice.onRoll, InfinityDice.totalRolls, InfinityDice.betPerRoll, InfinityDice.currentProfit);

        InfinityDice.onRoll += 1;

    },

    calculateMaxBet: function(rollUnder){
        // stay on the safe side so rolls don't fail...
        var profitMult = (100 / (rollUnderValue() - 1)).toString();
        var maxBet = InfinityDice.maxWinPerSpin.dividedBy(profitMult).times(0.95);
        
        return web3.fromWei(maxBet, "ether");
    },

    calculateMinBet: function(){
        return web3.fromWei(InfinityDice.minBet, "ether");
    },

    calculateProfit: function(betPerRoll, rollUnder){
        var profit = (100 / (rollUnder - 1) * ((100 - InfinityDice.houseEdge) / 100));
        console.log('profit', profit);
        return profit;
    }
}

$(document).ready(function(){
    initUI();
    InfinityDice.init();
    
});

function initUI(){
    //values for number rolls slider
    rollCountValues = [1,2,3,4,5,6,7,8,9,10,11,12,14,16,18,20,25,30,35,40,45,50,60,70,80,90,100,125,150,175,200,250,300,350,400,450,500,550,600,650,700,750,800,850,900,950,1024];
    
    //number rolls slider
    $('#number-rolls').slider({
        min: 0,
        max: rollCountValues.length - 1,
        value: 9,
        create: function(){
            $('#number-rolls-slider-handle').text(rollCountValues[$(this).slider("value")]);
        },
        slide: function(event, ui){
            $('#number-rolls-slider-handle').text(rollCountValues[ui.value].toString());
            updateGuaranteedRollsSlider_withUIInput(ui);
        }
    });

    // max and min buttons, double/half buttons
    $('#max-bet-per-roll').click(function(){
        var maxBet = InfinityDice.calculateMaxBet( parseFloat(rollUnderValue()) );
        $('#bet-per-roll').val(maxBet.toString());

        updateGuaranteedRollsSlider_withFixedRolls();
    });

    $('#double-bet-per-roll').click(function(){
        var maxBet = InfinityDice.calculateMaxBet( parseFloat(rollUnderValue()) );
        var doubleBet = parseFloat($('#bet-per-roll').val()) * 2;

        if (maxBet < doubleBet){
            $('#bet-per-roll').val(maxBet);
        }
        else {
            $('#bet-per-roll').val(doubleBet);
        }

        updateGuaranteedRollsSlider_withFixedRolls();
    });

    $('#half-bet-per-roll').click(function(){
        var minBet = InfinityDice.calculateMinBet();
        var halfBet = parseFloat($('#bet-per-roll').val()) / 2;
        
        if (minBet > halfBet){
            $('#bet-per-roll').val(minBet);
        }
        else {
            $('#bet-per-roll').val(halfBet);
        }

        updateGuaranteedRollsSlider_withFixedRolls();
    })

    $('#min-bet-per-roll').click(function(){
        $('#bet-per-roll').val(InfinityDice.calculateMinBet());

        updateGuaranteedRollsSlider_withFixedRolls();
    });

    $('#bet-per-roll').on('input', function(){
        updateGuaranteedRollsSlider_withFixedRolls();
    });

    // roll under slider
    $('#roll-under').slider({
        min: 2,
        max: 99,
        value: 50,
        create: function(){
            $('#roll-under-slider-handle').text($(this).slider("value"));
        },
        slide: function(event, ui){
            $('#roll-under-slider-handle').text(ui.value);

            var maxBet = InfinityDice.calculateMaxBet(parseFloat(ui.value));

            if ($('#bet-per-roll').val() > maxBet){
                $('#bet-per-roll').val(maxBet);
            }
            insertProfitPerRoll(ui.value);

            updateGuaranteedRollsSlider_withFixedRolls();
        }
    });

    $('#guaranteed-rolls').slider({
        min: 1,
        max: 10,
        value: 10,
        create: function(){
            $('#guaranteed-rolls-slider-handle').text($(this).slider("value"));
        },
        slide: function(event, ui){
            $('#guaranteed-rolls-slider-handle').text(ui.value);
        },
    })

    // tool tip to explain total bet
    $('#guaranteed-rolls-tooltip').tooltip();
}

///// helper functions to get the slider values //////
function rollUnderValue(){
    return $('#roll-under').slider('option', 'value');
}

function guaranteedRollsValue(){
    return $('#guaranteed-rolls').slider('option', 'value');
}

function numberRollsValue(){
    return rollCountValues[$('#number-rolls').slider('option', 'value')];
}
///////////////////////////////////////////////////////


function insertProfitPerRoll(rollUnderValue){
    var profit = InfinityDice.calculateProfit( parseFloat($('#bet-per-roll').val()), rollUnderValue );
    $('#your-profit-per-roll').html(profit.toString().slice(0,4) + 'x');
}

function updateGuaranteedRollsSlider_withUIInput(ui){
    var numberRolls = rollCountValues[ui.value];

    updateGuaranteedRollsSlider(numberRolls);
}

function updateGuaranteedRollsSlider_withFixedRolls(){
    var numberRolls = rollCountValues[$('#number-rolls').slider('option', 'value')];

    updateGuaranteedRollsSlider(numberRolls);
}

function updateGuaranteedRollsSlider(numberRolls){
    var betPerRoll = parseFloat($('#bet-per-roll').val());

    if (!isNaN(betPerRoll) && betPerRoll != 0){
        var maxPossibleRolls = Math.floor(web3.fromWei(InfinityDice.playerBalance, "ether") / betPerRoll);
        
        if (maxPossibleRolls < numberRolls){
            // change the max value to the max rolls possible
            $('#guaranteed-rolls').slider('option', 'max', maxPossibleRolls);

            if ($('#guaranteed-rolls').slider('option', 'value') > maxPossibleRolls){
                $('#guaranteed-rolls').slider('option', 'value', maxPossibleRolls);
            }
        }
        else {
            // change the max value to the number of rolls, cause the bettor has enough ether to get all the rolls
            $('#guaranteed-rolls').slider('option', 'max', numberRolls);

            if ($('#guaranteed-rolls').slider('option', 'value') > numberRolls){
                $('#guaranteed-rolls').slider('option', 'value', numberRolls);
            }
        }

        $('#guaranteed-rolls-slider-handle').text($('#guaranteed-rolls').slider('option', 'value'));
    }
}

function rollsReady(betPerRoll, totalProfit, maxRolls, rollUnder){
    // set values initially...
    $('#bet-size').text(web3.fromWei(betPerRoll, "ether").slice(0,8));
    $('#current-profit').text(web3.fromWei(totalProfit, "ether").slice(0,8));
    $('#max-rolls').text('0' + '/' + maxRolls.toString().slice(0,8));
    $('#lucky-number').html(rollUnder.toString().slice(0,8));

    // TODO: fade in and then fade out, instead of harsh hide <-> show
    $('#place-bets').hide();
    $('#roll-bets').show();
}

async function rollingDice(win, rollUnder, winSize, onRoll, totalRolls, betPerRoll, currentProfit){
    // disable the ROLL button
    $('#roll-dice').addClass('disabled');
    $('#roll-dice').off('click');

    var thisRoll;

    // break if the rolls are completed.
    if (onRoll >= totalRolls){
        return;
    }

    // do a simple animation
    var interval = 10;
    var rollAnimation = function(){
        
        // if the interval is small, then show a random number and increment the interval, then set another timeout with new interval
        if (interval < 500){

            interval *= 1.15;
            $('#your-number').text(Math.floor(Math.random() * 100) + 1);

            setTimeout(rollAnimation, interval);
        }
        // if the interval is large, then end the animation.
            // if the bettor won, then choose a random number below the rollUnder, and update the UI
            // if the bettor lost, then choose a random number above the rollUnder, ...
        else {
            if (! win){
                thisRoll = Math.floor(Math.random() * (100 - rollUnder) + (rollUnder + 1));

                $('#your-number').text(thisRoll);
                setTimeout( () => {
                    updateTicker(onRoll, totalRolls, currentProfit, {'color' : 'red'});
                }, 500);
            }

            else {
                thisRoll = Math.floor(Math.random() * (rollUnder - 1) + 1);
                
                $('#your-number').text(thisRoll);

                setTimeout( () => {
                    updateTicker(onRoll, totalRolls, currentProfit, {'color' : 'green'});
                }, 500); 
            }
             // enable the ROLL button once the roll has resolved.
             $('#roll-dice').removeClass('disabled');
             $('#roll-dice').click( () => {InfinityDice.rollDice()} );
            checkGameStatus(onRoll, totalRolls, currentProfit, betPerRoll);
        }
    }
    // start the timeout function
    setTimeout(rollAnimation, interval);
}

// purely a helper function for rolling dice to increment the ticker values.
function updateTicker(onRoll, totalRolls, currentProfit, cssColor){
    // increment the roll number color: white -> cssColor -> white
    $('#max-rolls').css(cssColor);
    $('#max-rolls').text(onRoll.toString() + '/' + totalRolls.toString());

    setTimeout( () => {
        $('#max-rolls').css({'color' : 'white'});
    }, 500);

    // change total profit, color white -> cssColor -> white
    $('#current-profit').css(cssColor);
    $('#current-profit').text(web3.fromWei(currentProfit, "ether").slice(0,8));

    setTimeout( () => {
        $('#current-profit').css({'color' : 'white'});
    }, 500);
}

function checkGameStatus(onRoll, totalRolls, currentProfit, betPerRoll){
    // check if the game has to end due to bankrupt player, or roll limit reached
    if (onRoll >= totalRolls || currentProfit.lessThan(betPerRoll)){

        $('#roll-dice').addClass('disabled');
        // TODO: animations needed
        setTimeout( () => {
            $('#roll-bets').hide();
            $('#place-bets').show();
            $('#roll-dice').removeClass('disabled');
        }, 5000)
    }
}







