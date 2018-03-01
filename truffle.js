module.exports = {
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      // kovan
      network_id: "42",
      gas: 6900000
    },
    live: {
    	host: "localhost",
    	port: 8545,
    	network_id: "1",
    	gas: 7900000
    }
  }
};
