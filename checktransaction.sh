#!/usr/bin/env bash

. "$(dirname "$0")/inc.common.sh"

if [ "$1" == "" ]; then
    echo "Usage: $(basename "$0") [options] txid|address [blockhash]"
    echo "Where:"
    echo "  txid        - transaction id"
    echo "  address     - Bitcoin address (shows transactions received to address)"
    echo "  blockhash   - optional blockhash for a block where to look for a non-wallet / non-mempool tx"
    exit
fi

check_multiwallet

txids=()

if is_valid_bitcoin_address "$1"; then
    addr_txids=$(call_bitcoin_cli listreceivedbyaddress 0 true true "$1" | jq -r ".[].txids[]")
    if [ "$addr_txids" != "" ]; then
        while read txid; do
            txids+=("$txid")
        done <<< "$addr_txids"
    fi
else
    txids+=("$1")
fi

blockhash="$2"

if (( ${#txids[@]} == 0 )); then
    echo "No known transactions."
    exit
fi

for i in $(seq 0 $(( ${#txids[@]} - 1 )) ); do
    show_decoded_tx_for_human "$(show_tx_by_id "${txids[$i]}" "$blockhash")"
    echo
done
