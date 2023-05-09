#!/usr/bin/env bash

# shellcheck disable=SC1091
# shellcheck source=./inc.common.sh
. "$(dirname "$(readlink -m "$0")")/inc.common.sh"

if [ "$1" == "" ]; then
    echo "Usage: $(basename "$0") [options] txid|address|rawtx [blockhash]"
    echo "Where:"
    echo "  txid        - transaction id (either plain hex or blockchain explorer URL containing it)"
    echo "  address     - Bitcoin address (shows transactions received to address)"
    echo "  rawtx       - raw transaction hex"
    echo "  blockhash   - optional blockhash for a block where to look for a non-wallet / non-mempool tx"
    exit
fi

if ! has_index "txindex"; then
    check_multiwallet
fi

txids=()

if is_valid_bitcoin_address "$1"; then
    addr_txids=$(call_bitcoin_cli listreceivedbyaddress 0 true true "$1" | jq -r ".[].txids[]")
    if [ "$addr_txids" != "" ]; then
        while read -r txid; do
            txids+=("$txid")
        done <<< "$addr_txids"
    fi
elif is_http_url "$1"; then
    txid="$(get_hex_id_from_string "$1" "64")"
    if [ "$txid" == "" ]; then
        echo "URL $1 does not contain 64-byte hex Bitcoin transaction id."
        exit 2
    fi
    txids+=("$txid")
elif is_hex_id "$1" "64"; then
    txids+=("$1")
elif is_hex_string "$1"; then
    txids+=("raw")
    rawtx="$1"
else
    echo "'$1' is neither valid transacion id nor address nor HTTP URL."
    exit 2
fi

blockhash="$2"

if (( ${#txids[@]} == 0 )); then
    echo "No known transactions."
    exit
fi

for i in $(seq 0 $(( ${#txids[@]} - 1 )) ); do
    if [[ "${txids[$i]}" == "raw" ]]; then
        decoded_tx="$(call_bitcoin_cli -stdin decoderawtransaction <<< "$rawtx")"
    else
        decoded_tx="$(show_tx_by_id "${txids[$i]}" "$blockhash")"
    fi
    show_decoded_tx_for_human "$decoded_tx"
    echo
done
