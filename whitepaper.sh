#!/usr/bin/env bash
# Based on https://bitcoin.stackexchange.com/a/35970/23146 by Jimmy Song

. $(dirname $0)/inc.common.sh

if [ "$1" == "" ]; then
    echo "Usage: $(basename "$0") bitcoin.pdf"
    exit 1
fi

outfile="$1"

rawtx="$(call_bitcoin_cli getrawtransaction \
    54e48e5f5c656b26c3bca14a8c95aa583d07ebe84dde3b7dd4a78f4e4186e713 \
    false \
    00000000000000ecbbff6bafb7efa2f7df05b227d5c73dca8f2635af32a2e949)"

if [ "$rawtx" == "" ]; then
    echo "Couldn't find tx 54e48e5f5c656b26c3bca14a8c95aa583d07ebe84dde3b7dd4a78f4e4186e713."
    echo "Are you sure you are on the mainnet?"
    exit 2
fi

delimiter="0100000000000000"
readarray -t outputs < <(echo "$rawtx" | sed "s/$delimiter/\\n/g")

pdfhex=""
for i in $(seq 1 $(( ${#outputs[@]} - 3 )) ); do
    output="${outputs[$i]}"
    # there are 3 65-byte parts in this that we need
    cur=6
    pdfhex+="${output:$cur:130}"
    cur=$(( $cur + 132 ))
    pdfhex+="${output:$cur:130}"
    cur=$(( $cur + 132 ))
    pdfhex+="${output:$cur:130}"
done
output="${outputs[$(( ${#outputs[@]} - 2 ))]}"
pdfhex+="${output:6:-20}"

echo -n "${pdfhex:16}" | xxd -r -p > "$outfile"
