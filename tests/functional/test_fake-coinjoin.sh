#!/usr/bin/env bash
# shellcheck disable=SC2034

# shellcheck source=/dev/null
. "$(dirname "$0")/inc.setup.sh"

for address_type in legacy p2sh-segwit bech32; do
    destination_addresses=()
    for i in $(seq 0 2); do
        destination_addresses+=("$($bitcoin_cli getnewaddress "" "$address_type")")
    done

    echo

    echo y | "$(dirname "$0")/../../fake-coinjoin.sh" "${bitcoin_args[@]:?}" 1 "${destination_addresses[@]}" || retval=1

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
done

. "$(dirname "$0")/inc.teardown.sh"

