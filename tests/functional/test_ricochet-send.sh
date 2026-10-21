#!/usr/bin/env bash
# shellcheck disable=SC2034

# shellcheck source=/dev/null
. "$(dirname "$0")/inc.setup.sh"

has_fee_rate=0
if $bitcoin_cli help sendtoaddress | grep -q 'fee_rate'; then
    has_fee_rate=1
fi

# Check actual regtest transactions, including the initial wallet transaction.
# Fee arguments remain BTC/kvB; measured rates below are sat/vB.
check_ricochet()
{
    local rate="$1" factor="$2" minimum_rate="$3" maximum_rate="$4"
    local destination_address output first_txid decoded fee_sats vsize paytxfee_before paytxfee_after
    destination_address="$($bitcoin_cli getnewaddress)"
    paytxfee_before="$($bitcoin_cli getwalletinfo | jq -r '.paytxfee')"
    output="$(echo y | "$(dirname "$0")/../../ricochet-send.sh" \
        "${bitcoin_args[@]:?}" 1 "$destination_address" 4 "$rate" 0 1 0 "$factor")" || return 1
    echo "$output"
    first_txid="$(sed -nE 's/^0: .* - ([0-9a-f]{64})$/\1/p' <<< "$output")"
    if [[ -z "$first_txid" ]]; then
        echo "Missing initial transaction id"
        return 1
    fi
    decoded="$($bitcoin_cli getrawtransaction "$first_txid" true)" || return 1
    vsize="$(jq -r '.vsize' <<< "$decoded")"
    fee_sats="$($bitcoin_cli gettransaction "$first_txid" | jq -r '.fee * -100000000')"
    # Core rounds the total fee to whole satoshis. Allow at most one satoshi
    # of rounding, rather than comparing a rounded fee/vsize quotient.
    if [[ "$(echo "$fee_sats >= $minimum_rate * $vsize - 1 && $fee_sats <= $maximum_rate * $vsize + 1" | bc)" != 1 ]]; then
        echo "Unexpected initial fee: $fee_sats sat for $vsize vB (expected $minimum_rate..$maximum_rate sat/vB)"
        return 1
    fi
    if [[ "$($bitcoin_cli getreceivedbyaddress "$destination_address" 0)" != "1.00000000" ]]; then
        echo "Unexpected amount at destination"
        return 1
    fi
    paytxfee_after="$($bitcoin_cli getwalletinfo | jq -r '.paytxfee')"
    if [[ "$has_fee_rate" == 1 && "$paytxfee_after" != "$paytxfee_before" ]]; then
        echo "Per-transaction fee changed wallet paytxfee"
        return 1
    fi
}

# Exact conversion, including a fractional sat/vB rate.
check_ricochet 0.00002000 0 2 2 || retval=1
check_ricochet 0.00001234 0 1.234 1.234 || retval=1
# Default and custom randomization ranges.
check_ricochet 0.00002000 0.3 1.4 2.6 || retval=1
check_ricochet 0.00002000 0.2 1.6 2.4 || retval=1
# The selected minimum is raised to the node's mempool floor.
mempool_rate="$($bitcoin_cli getmempoolinfo | jq -r '.mempoolminfee * 100000')"
check_ricochet 0.00000999 0.3 "$mempool_rate" 1.2987 || retval=1

. "$(dirname "$0")/inc.teardown.sh"
