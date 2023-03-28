#!/usr/bin/env bash
# shellcheck disable=SC2034

# shellcheck source=/dev/null
. "$(dirname "$0")/inc.setup.sh"

destination_addresses=()
for i in $(seq 0 2); do
    destination_addresses+=("$($bitcoin_cli getnewaddress "" "p2sh-segwit")")
done

echo

echo y | "$(dirname "$0")/../../fake-coinjoin.sh" "${bitcoin_args[@]:?}" 1 "${destination_addresses[@]}"

for i in $(seq 0 2); do
    destination_amount="$($bitcoin_cli getreceivedbyaddress "${destination_addresses[$i]}" 0)"
    if [ "$destination_amount" != "1.00000000" ]; then
        echo "Unexpected amount at destination $i: $destination_amount"
        retval=1
    fi
done

# tick chain forward
$bitcoin_cli generatetoaddress 1 "$($bitcoin_cli getnewaddress)"

cjtxids="$("$(dirname "$0")/../../listpossiblecjtxids.sh" "${bitcoin_args[@]:?}" "$($bitcoin_cli getblockcount)")"
cjtxids_count="$(( $(wc -l <<< "$cjtxids") - 1))"
if (( cjtxids_count != 1 )); then
    echo "Unexpected cj tx id count $cjtxids_count in last block"
    echo "$cjtxids"
    retval=1
fi

. "$(dirname "$0")/inc.teardown.sh"

