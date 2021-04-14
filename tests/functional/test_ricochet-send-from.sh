#!/usr/bin/env bash
# shellcheck disable=SC2034

# shellcheck source=/dev/null
. "$(dirname "$0")/inc.setup.sh"

source_address="$(${bitcoin_cli:?} getnewaddress)"
$bitcoin_cli sendtoaddress "$source_address" 2

destination_address="$($bitcoin_cli getnewaddress)"
echo y | "$(dirname "$0")/../../ricochet-send-from.sh" \
    "${bitcoin_args[@]:?}" "$source_address" "$destination_address" \
    "4" "0.00000999"

source_unspent_count="$($bitcoin_cli listunspent 0 999999 "[\"$source_address\"]" | jq ". | length")"
if [ "$source_unspent_count" != "0" ]; then
    echo "Unexpected unspent count at source address: $source_unspent_count"
    retval=1
fi

destination_unspent_count="$($bitcoin_cli listunspent 0 999999 "[\"$destination_address\"]" | jq ". | length")"
if [ "$destination_unspent_count" != "1" ]; then
    echo "Unexpected unspent count at destination address: $destination_unspent_count"
    retval=1
fi

destination_amount="$($bitcoin_cli getreceivedbyaddress "$destination_address" 0)"
if [ "$destination_amount" == "0.00000000" ]; then
    echo "Unexpected amount at destination: $destination_amount"
    retval=1
fi

. "$(dirname "$0")/inc.teardown.sh"

