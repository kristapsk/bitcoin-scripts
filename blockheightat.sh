#!/usr/bin/env bash

# shellcheck disable=SC1091
# shellcheck source=./inc.common.sh
. "$(dirname "$(readlink -m "$0")")/inc.common.sh"

if [ "$1" == "" ]; then
    echo "Usage: $(basename "$0") [options] timestr"
    echo "Where:"
    echo "  timestr     - any date/time string recognized by date command"
    exit 0
fi

target_timestr="$1"
target_unixtime=$(date -d "$1" +"%s")

function get_time_at_height()
{
    call_bitcoin_cli getblockheader \
        "$(call_bitcoin_cli getblockhash "$1")" | jq ".time"
}

start_height=1
start_unixtime=$(get_time_at_height $start_height)

if (( target_unixtime < start_unixtime )); then
    echoerr "Requested target time $target_timestr ($target_unixtime) is before block height 1 ($start_unixtime)"
    exit 1
fi

end_height=$(call_bitcoin_cli getblockchaininfo | jq ".blocks")
end_unixtime=$(get_time_at_height "$end_height")

if (( target_unixtime >= end_unixtime )); then
    echo "$end_height"
    exit 0
fi

while (( $(( end_height - start_height )) > 1 )); do
    current_height=$(( start_height + (end_height - start_height) / 2 ))
    current_unixtime=$(get_time_at_height "$current_height")
    if (( current_unixtime > target_unixtime )); then
        end_height=$((current_height--))
        end_unixtime=$(get_time_at_height "$end_height")
    elif (( current_unixtime < target_unixtime )); then
        start_height=$((current_height++))
        start_unixtime=$(get_time_at_height "$start_height")
    fi
done

echo "$start_height"
