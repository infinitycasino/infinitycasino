// general javascript for infinity casino

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