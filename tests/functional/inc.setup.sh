# shellcheck shell=bash

bitcoin_args="-regtest"
bitcoind="bitcoind $bitcoin_args -fallbackfee=0.0002"
bitcoin_cli="bitcoin-cli $bitcoin_args"

# shellcheck disable=SC2034
retval=0

$bitcoind -daemon || exit 1
# Wait until bitcoind has started properly
while ! $bitcoin_cli getblockchaininfo &> /dev/null; do sleep 0.1; done
# Create and load wallet
$bitcoin_cli createwallet tests
$bitcoin_cli loadwallet tests
# Generate some coins
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress "" "legacy")"
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress "" "legacy")"
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress "" "legacy")"
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress "" "p2sh-segwit")"
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress "" "p2sh-segwit")"
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress "" "p2sh-segwit")"
# 120 blocks more, so that coins above are spendable
$bitcoin_cli generatetoaddress 120 "$($bitcoin_cli getnewaddress)"
