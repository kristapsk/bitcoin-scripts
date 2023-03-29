#!/usr/bin/env bash

# shellcheck disable=SC1091
# shellcheck source=./inc.common.sh
. "$(dirname "$(readlink -m "$0")")/inc.common.sh"

if [ "$1" == "" ]; then
    echo "Usage: $(basename "$0") bitcoin.pdf"
    exit 1
fi

outfile="$1"

wp_txid="54e48e5f5c656b26c3bca14a8c95aa583d07ebe84dde3b7dd4a78f4e4186e713"
wp_blockhash="00000000000000ecbbff6bafb7efa2f7df05b227d5c73dca8f2635af32a2e949"

# First, try getting it from the blockchain. It is fastest approach, but is
# not compatible with pruning.
# Based on https://bitcoin.stackexchange.com/a/35970/23146 by Jimmy Song.
rawtx="$(try_bitcoin_cli getrawtransaction "$wp_txid" false "$wp_blockhash")"
if [ "$rawtx" != "" ]; then
    delimiter="0100000000000000"
    readarray -t outputs < <(echo "${rawtx//$delimiter/\\n}")
    need_skip="6"
    first="1"
    last="$(( ${#outputs[@]} - 3 ))"
else
    # Alternative approach is to get it from the UTXO set, as it was encoded
    # in bare multisig outputs that will never be spent. Will work with pruned
    # nodes too.
    # See https://github.com/kristapsk/bitcoin-scripts/issues/9
    outputs=()
    for i in $(seq 0 945); do
        outputs+=( "$(call_bitcoin_cli gettxout "$wp_txid" "$i" | \
            jq -r ".scriptPubKey.hex")" )
    done
    need_skip="4"
    first="0"
    last="$(( ${#outputs[@]} - 2 ))"
fi

pdfhex=""
for i in $(seq $first $last); do
    output="${outputs[$i]}"
    cur="$need_skip"
    # there are 3 65-byte parts in this that we need
    pdfhex+="${output:$cur:130}"
    cur=$(( cur + 132 ))
    pdfhex+="${output:$cur:130}"
    cur=$(( cur + 132 ))
    pdfhex+="${output:$cur:130}"
done
output="${outputs[$(( last + 1 ))]}"
pdfhex+="${output:$need_skip:50}"

echo -n "${pdfhex:16}" | xxd -r -p > "$outfile"
