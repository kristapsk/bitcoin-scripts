#!/usr/bin/env bash

# shellcheck source=/dev/null
. "$(dirname "$0")/inc.common.sh"

if [ "$1" == "" ]; then
    echo "Usage: $(basename "$0") blockheight"
    exit
fi

blockheight="$1"
blockhash="$(call_bitcoin_cli getblockhash "$blockheight")"

echo "Block $blockheight ($blockhash)"

while read -r txid; do
    txdata="$(call_bitcoin_cli getrawtransaction "$txid" true "$blockhash")"
    if [ "$(is_likely_cj_tx "$txdata")" ]; then
        echo "$txid"
    fi
done < <(call_bitcoin_cli getblock "$blockhash" | jq -r ".tx[]")
