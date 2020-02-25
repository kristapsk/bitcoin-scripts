#!/usr/bin/env bash
# shellcheck disable=SC2034

# shellcheck source=/dev/null
. "$(dirname "$0")/inc.setup.sh"

destination_address="$(${bitcoin_cli:?} getnewaddress)"
echo y | "$(dirname "$0")/../../ricochet-send.sh" -regtest 1 "$destination_address"

destination_amount="$($bitcoin_cli getreceivedbyaddress "$destination_address" 0)"
if [ "$destination_amount" != "1.00000000" ]; then
    echo "Unexpected amount at destination: $destination_amount"
    retval=1
fi

. "$(dirname "$0")/inc.teardown.sh"

