#!/usr/bin/env bash

# shellcheck source=/dev/null
. "$(dirname "$(readlink -m "$0")")/inc.common.sh"

if [ "$1" == "" ]; then
    echo "Usage: $(basename "$0") blockhash|blockheight"
    exit
fi

block="$1"
if grep -qE "[0-9a-z]{32}" <<< "$block"; then
    blockhash="$block"
    blockheight="$(call_bitcoin_cli getblockheader "$block" | jq ".height")"
else
    blockheight="$block"
    blockhash="$(call_bitcoin_cli getblockhash "$block")"
fi

echo "Block $blockheight ($blockhash)"

while read -r txid; do
    txdata="$(call_bitcoin_cli getrawtransaction "$txid" true "$blockhash")"
    if is_likely_cj_tx "$txdata"; then
        echo "$txid"
    fi
done < <(call_bitcoin_cli getblock "$blockhash" | jq -r ".tx[]")
