#!/usr/bin/env bash

. "$(dirname "$0")/inc.common.sh"

if [ "$1" == "" ]; then
    echo "Usage: $(basename "$0") [options] txid|address"
    echo "Where:"
    echo "  txid    - transaction id"
    echo "  address - Bitcoin address"
    exit
fi

check_multiwallet

txids=()

if is_valid_bitcoin_address "$1"; then
    addr_txids=$(call_bitcoin_cli listreceivedbyaddress 0 true true "$1" | jq -r ".[].txids[]")
    if (( ${#addr_txids[@]} > 0 )); then
        for i in $(seq 0 $(( ${#addr_txids[@]} - 1 )) ); do
            txids+=("${addr_txids[$i]}")
        done
    fi
else
    txids+=("$1")
fi

if (( ${#txids[@]} == 0 )); then
    echo "No transactions."
    exit
fi

for i in $(seq 0 $(( ${#txids[@]} - 1 )) ); do
    show_decoded_tx_for_human "$(show_tx_by_id "${txids[$i]}")"
done
