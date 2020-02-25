# shellcheck shell=bash

bitcoind=bitcoind
bitcoin_cli="bitcoin-cli -regtest"

# shellcheck disable=SC2034
retval=0

$bitcoind -regtest -daemon || exit 1
# Wait until bitcoind has started properly
while ! $bitcoin_cli getblockchaininfo &> /dev/null; do sleep 0.1; done
# Generate some coins
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress)"
