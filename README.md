# Welcome to Infinity Casino!
### We are a fully decentralized blockchain gambling site utilizing ethereum smart contracts.
#### This is the testing branch of our github. To start automated testing, follow these instructions...

**WARNING** DO NOT MERGE THIS BRANCH WITH MASTER. THIS CONTAINS SOME SMALL SMART CONTRACT MODIFICATIONS WHICH ARE NECESSARY TO TEST ON LOCALHOST!

1. npm install ethereumjs-testrpc
2. npm install truffle
3. git clone https://github.com/oraclize/ethereum-bridge
4. git clone https://github.com/infinitycasino/infinitycasino/tree/DANGER-testrpc-testing-branch-smart-contract-mods
5. cd ethereum-bridge/ && npm install

Now that these prerequisites are installed, we can start testrpc and ethereum-bridge. Testrpc allows one to spin up a temporary test blockchain on localhost, and ethereum-bridge allows our contracts to use oraclize functionality on our localhost-chain.
1. testrpc -l 7900000 -m "infinitycasino"  (this starts testrpc with gas limit of 7,900,000 and deterministic account memnomic "infinitycasino")
2. node bridge -H localhost:8545 -a 9 --dev (make sure you are in ./ethereum-bridge to run this, this starts the oraclize service)
3. truffle test (make sure you are in ./infinitycasino to run this, this will run our automated tests with truffle!)

Problems? Bug reports? Please email development@infinitycasino.io or start an issue right here on GitHub!

Support requests? Please email support@infinitycasino.io and we will respond right away!