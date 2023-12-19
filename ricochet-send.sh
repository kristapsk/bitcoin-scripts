#!/usr/bin/env bash

# shellcheck disable=SC1091
# shellcheck source=./inc.common.sh
. "$(dirname "$(readlink -m "$0")")/inc.common.sh"

if [ "$2" == "" ]; then
    echo "Usage: $(basename "$0") [options] amount destination_address [hops [txfee [sleeptime_min [sleeptime_max [hop_confirmations [txfee_factor]]]]]]"
    echo "Where:"
    echo "  amount              - amount to send in BTC"
    echo "  destination_address - destination address"
    echo "  hops                - number of hops (default: 5)"
    echo "  txfee               - average transaction fee per kvB (default: \"estimatesmartfee 2\", currently $($(dirname "$(readlink -m "$0")")/estimatesmartfee.sh $bitcoin_cli_options 2) BTC)"
    echo "  sleeptime_min       - minimum sleep time between hops in seconds (default: 10)"
    echo "  sleeptime_max       - maximum sleep time between hops in seconds (default: 15)"
    echo "  hop_confirmations   - minimum number of confirmations between hops (default: 0)"
    echo "  txfee_factor        - variance around average transaction fee, e.g. 0.00002000 fee, 0.2 var = fee is between 0.00001600 and 0.00002400 (default: 0.3)"
    exit
fi

check_multiwallet

amount=$1
address=$2
if ! is_valid_bitcoin_address "$address"; then
    echoerr "Invalid Bitcoin address $address"
    exit 1
fi

hops=5
sleeptime_min=10
sleeptime_max=15

if [ "$3" != "" ]; then
    hops=$3
fi
if [ "$4" != "" ]; then
    txfee="$4"
else
    txfee="$($(dirname "$(readlink -m "$0")")/estimatesmartfee.sh $bitcoin_cli_options 2)"
fi
if [ "$6" != "" ]; then
    sleeptime_min=$5
    sleeptime_max=$6
elif [ "$5" != "" ]; then
    sleeptime_min=$5
    sleeptime_max=$5
fi
if [ "$7" != "" ]; then
    hop_confirmations=$7
else
    hop_confirmations=0
fi
if [ "$8" != "" ]; then
    txfee_factor="$8"
else
    txfee_factor="0.3"
fi

# Force minimum required fee
txfee_min="$(bc_float_calc "$txfee * (1 - $txfee_factor)")"
txfee_max="$(bc_float_calc "$txfee * (1 + $txfee_factor)")"
mempoolminfee="$(call_bitcoin_cli getmempoolinfo | jq_btc_float ".mempoolminfee")"
if is_btc_lt "$txfee_min" "$mempoolminfee"; then
    echo "Feerate $txfee_min is below minimum mempool fee, raising minimum to $mempoolminfee"
    txfee_min="$mempoolminfee"
fi
txfee_average="$(bc_float_calc "($txfee_min + $txfee_max) * 0.5")"

echo "Ricocheting $amount BTC to $address via $hops hops using average $txfee_average fee per kvB"
read -p "Is this ok? " -n 1 -r
echo

if ! [[ $REPLY =~ ^[Yy]$ ]]; then
    exit
fi

PREPARE_START="$(date +%s.%N)"

# We use P2PKH addresses for ricochet hops for now, that's easer.
ricochet_addresses=()
for i in $(seq 1 $(( hops - 1 ))); do
#    ricochet_addresses+=("$(call_bitcoin_cli getnewaddress)")
    ricochet_addresses+=("$(getnewaddress_p2pkh)")
done
ricochet_addresses+=("$address")

# FixMe: TX size may vary depending on input and output address types
ricochet_tx_size=192
ricochet_fees=(
    "$(randamount "$txfee_min" "$txfee_max")"
)
ricochet_fee_sum="0"
for i in $(seq 1 $(( hops - 1 ))); do
    fee="$(randamount "$txfee_min" "$txfee_max")"
    ricochet_fees+=("$fee")
    ricochet_fee_sum="$(bc_float_calc "$ricochet_fee_sum + $fee")"
done
ricochet_fees+=("0")
send_amount=$(bc_float_calc "$amount + $ricochet_fee_sum")

#echo "Richochet addresses: ${ricochet_addresses[@]}"
#echo "Ricochet fees: ${ricochet_fees[@]}"

# Send out first transaction
echo -n "0: (wallet) -> ${ricochet_addresses[0]} ($send_amount) - "
call_bitcoin_cli settxfee "${ricochet_fees[0]}" > /dev/null
txid="$(call_bitcoin_cli sendtoaddress "${ricochet_addresses[0]}" "$send_amount")"
echo "$txid"
rawtx="$(show_tx_by_id "$txid")"
#echo "$rawtx"
vout_idx=""
idx=0
while read -u 3 -r vout_address; do
    if [ "$vout_address" == "${ricochet_addresses[0]}" ]; then
        vout_idx=$idx
        value="$(echo "$rawtx" | jq -r ".vout[$vout_idx].value")"
        if [ "$value" == "$send_amount" ]; then
            prev_pubkey="$(echo "$rawtx" | jq -r ".vout[$vout_idx].scriptPubKey.hex")"
            break
        fi
    fi
    ((idx++))
done 3< <(get_decoded_tx_addresses "$rawtx")
if [ "$prev_pubkey" == "" ]; then
    echoerr "$rawtx"
    echoerr "FATAL: Can't find the right vout in the first transaction, please fill a bug report!"
    echoerr "Expecting $send_amount -> ${ricochet_addresses[0]}"
    exit 1
fi

use_txid="$txid"

# Prepare and sign rest of transactions
echo "Preparing rest of transactions..."
signedtxes=()
for i in $(seq 1 $(( hops - 1 ))); do
    send_amount="$(bc_float_calc "$send_amount - ${ricochet_fees[$i]}")"
    echo -n "$i: ${ricochet_addresses[$(( i - 1 ))]} -> ${ricochet_addresses[$i]} ($send_amount) - "
    rawtx="$(call_bitcoin_cli createrawtransaction "[{\"txid\":\"$use_txid\",\"vout\":$vout_idx}]" "{\"${ricochet_addresses[$i]}\":$send_amount}")"
    privkey="$(call_bitcoin_cli dumpprivkey "${ricochet_addresses[$(( i - 1 ))]}")"
    signedtx="$(signrawtransactionwithkey "$rawtx" "[\"$privkey\"]" "[{\"txid\":\"$use_txid\",\"vout\":$vout_idx,\"scriptPubKey\":\"$prev_pubkey\",\"amount\":$send_amount}]")"
    decodedtx="$(call_bitcoin_cli decoderawtransaction "$signedtx")"
    use_txid="$(echo "$decodedtx" | jq -r ".txid")"
    signedtxes+=("$signedtx")
    vout_idx=0
    prev_pubkey="$(echo "$decodedtx" | jq -r ".vout[].scriptPubKey.hex")"
    echo "$use_txid"
done

#printf '%s\n' "${signedtxes[@]}"

PREPARE_DURATION="$(echo "$(date +%s.%N) - $PREPARE_START" | bc)"
LANG=POSIX printf \
    "Initial transaction preparing took %.6f seconds (you can lock wallet now)\n" \
    "$PREPARE_DURATION"

# Broadcast transactions with delays
echo "Sending transactions..."
for i in $(seq 1 $(( hops - 1 ))); do
    if [ "$hop_confirmations" != "0" ]; then
        echo "Waiting for $hop_confirmations transaction confirmation(s)..."
        wait_for_tx_confirmations "$txid" "$hop_confirmations"
    fi
    random_delay=$(( RANDOM % (sleeptime_max - sleeptime_min) + sleeptime_min ))
    echo "Sleeping for $random_delay second(s)..."
    sleep $random_delay
    echo "$i: $(call_bitcoin_cli sendrawtransaction "${signedtxes[$(( i - 1 ))]}")"
    txid="$(call_bitcoin_cli decoderawtransaction "${signedtxes[$(( i - 1 ))]}" | jq -r ".txid")"
done
