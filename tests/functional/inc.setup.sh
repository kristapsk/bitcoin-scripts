# shellcheck shell=bash

bitcoin_root=""
bitcoin_test_datadir="$(mktemp)"
bitcoin_args=(
    "-regtest"
    "-datadir=$bitcoin_test_datadir"
)
bitcoind="bitcoind ${bitcoin_args[*]} -fallbackfee=0.0002"
bitcoin_cli="bitcoin-cli ${bitcoin_args[*]}"
if [[ -n $bitcoin_root ]]; then
    bitcoind="$bitcoin_root/$bitcoind"
    bitcoin_cli="$bitcoin_root/$bitcoin_cli"
fi

# shellcheck disable=SC2034
retval=0

set -x

rm -rf "$bitcoin_test_datadir"
mkdir "$bitcoin_test_datadir"
echo -e "[regtest]\nrpcuser=bitcoinrpc\nrpcpassword=123456abcdef" \
    > "$bitcoin_test_datadir/bitcoin.conf"
if [[ "$($bitcoind -version | grep -Eo 'v[0-9]+')" == "v26" ]]; then
    echo "deprecatedrpc=create_bdb" >> "$bitcoin_test_datadir}/bitcoin.conf"
fi
$bitcoind -daemon || exit 1
# Wait until bitcoind has started properly
while ! $bitcoin_cli getblockchaininfo 2> /dev/null; do sleep 0.1; done
# Create and load wallet if there is no default wallet (descriptor wallets aren't supported yet)
if [[ "$($bitcoin_cli listwallets | jq ". | length")" == "0" ]]; then
    if ! $bitcoin_cli -named createwallet wallet_name=tests descriptors=false 2> /dev/null; then
        # fallback for old Core versions
        $bitcoin_cli createwallet tests
    fi
fi
#$bitcoin_cli loadwallet tests
# Generate some coins
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress "" "legacy")"
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress "" "legacy")"
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress "" "legacy")"
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress "" "p2sh-segwit")"
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress "" "p2sh-segwit")"
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress "" "p2sh-segwit")"
# 120 blocks more, so that coins above are spendable
$bitcoin_cli generatetoaddress 120 "$($bitcoin_cli getnewaddress)"
