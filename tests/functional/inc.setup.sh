# shellcheck shell=bash

bitcoin_root=""
bitcoin_test_datadir="$(mktemp -d)"
wallet_type="${WALLET_TYPE:-legacy}"
case "$wallet_type" in
    legacy|descriptor) ;;
    *) echo "Unknown WALLET_TYPE: $wallet_type"; exit 1 ;;
esac
bitcoin_args=(
    "-regtest"
    "-datadir=$bitcoin_test_datadir"
)
# Keep the fee-floor regression deterministic across Core defaults.
bitcoind="bitcoind ${bitcoin_args[*]} -fallbackfee=0.0002 -minrelaytxfee=0.00001"
bitcoin_cli="bitcoin-cli ${bitcoin_args[*]}"
if [[ -n $bitcoin_root ]]; then
    bitcoind="$bitcoin_root/$bitcoind"
    bitcoin_cli="$bitcoin_root/$bitcoin_cli"
fi

# shellcheck disable=SC2034
retval=0

#set -x

echo -e "[regtest]\nrpcuser=bitcoinrpc\nrpcpassword=123456abcdef" \
    > "$bitcoin_test_datadir/bitcoin.conf"
$bitcoind -daemon || exit 1
# Wait until bitcoind has started properly
while ! $bitcoin_cli getblockchaininfo 2> /dev/null; do sleep 0.1; done
# Keep the pre-descriptor Core path, but never silently fall back when
# descriptor coverage was requested.
if [[ "$wallet_type" == descriptor ]]; then
    $bitcoin_cli -named createwallet wallet_name=tests descriptors=true || exit 1
elif [[ "$($bitcoin_cli listwallets | jq ". | length")" == "0" ]]; then
    if ! $bitcoin_cli -named createwallet wallet_name=tests descriptors=false 2> /dev/null; then
        $bitcoin_cli createwallet tests || exit 1
    fi
fi
actual_descriptors="$($bitcoin_cli getwalletinfo | jq -r '.descriptors // false')"
if [[ "$wallet_type" == descriptor && "$actual_descriptors" != true ]] ||
   [[ "$wallet_type" == legacy && "$actual_descriptors" != false ]]; then
    echo "Unexpected wallet type: $actual_descriptors"
    $bitcoin_cli stop
    exit 1
fi
# Generate some coins
for address_type in legacy p2sh-segwit bech32; do
    for i in 1 2 3; do
        $bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress "" "$address_type")"
    done
done
# Mature the funding outputs.
$bitcoin_cli generatetoaddress 120 "$($bitcoin_cli getnewaddress)"
