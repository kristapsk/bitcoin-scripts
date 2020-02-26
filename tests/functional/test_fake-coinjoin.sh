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

. "$(dirname "$0")/inc.teardown.sh"

