#! /bin/bash

. $(dirname $0)/inc.common.sh

if [ "$2" == "" ]; then
    echo "Usage: $(basename $0) [options] amount destination_address [hops [fee [sleeptime_min [sleeptime_max]]]]"
    exit
fi

amount=$1
address=$2
if ! is_valid_bitcoin_address $address; then
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
    fee=$4
else
    fee=$($(dirname $0)/estimatesmartfee.sh $bitcoin_cli_options 2)
fi
if [ "$6" != "" ]; then
    sleeptime_min=$5
    sleeptime_max=$6
elif [ "$5" != "" ]; then
    sleeptime_min=$5
    sleeptime_max=$5
fi

# Force minimum required fee
fee=$(echo "$fee" | btc_amount_format)
minrelayfee=$(call_bitcoin_cli getnetworkinfo | jq_btc_float ".relayfee")
if is_btc_lt "$fee" "$minrelayfee"; then
    echo "Fee $fee is below minimum relay fee, raising to $minrelayfee"
    fee=$minrelayfee
fi

echo "Ricocheting $amount BTC to $address via $hops hops using $fee fee per KB"
read -p "Is this ok? " -n 1 -r
echo

if ! [[ $REPLY =~ ^[Yy]$ ]]; then
    echo NOT
    exit
fi

PREPARE_START="$(date +%s.%N)"

# We use P2PKH addresses for ricochet hops for now, that's easer.
ricochet_addresses=()
for i in $(seq 1 $(( $hops - 1 ))); do
#    ricochet_addresses+=("$(call_bitcoin_cli getnewaddress)")
    ricochet_addresses+=("$(getnewaddress_p2pkh)")
done
ricochet_addresses+=("$address")

# FixMe: TX size may vary depending on input and output address types
ricochet_tx_size=192
single_ricochet_tx_fee=$(bc_float_calc "$ricochet_tx_size * $fee * 0.001")
ricochet_fees=$(bc_float_calc "($hops - 1) * $single_ricochet_tx_fee")
send_amount=$(bc_float_calc "$amount + $ricochet_fees")

#echo "Richochet addresses: ${ricochet_addresses[@]}"

# Send out first transaction
echo -n "0: (wallet) -> ${ricochet_addresses[0]} ($send_amount) - "
call_bitcoin_cli settxfee $fee > /dev/null
txid=$(call_bitcoin_cli sendtoaddress ${ricochet_addresses[0]} $send_amount)
echo "$txid"
rawtx=$(show_tx_by_id $txid)
#echo "$rawtx"
vout_idx=""
idx=0
while read vout_address; do
    if [ "$vout_address" == "${ricochet_addresses[0]}" ]; then
        vout_idx=$idx
        value="$(echo "$rawtx" | jq -r ".vout[$vout_idx].value")"
        if [ "$value" == "$send_amount" ]; then
            prev_pubkey="$(echo "$rawtx" | jq -r ".vout[$vout_idx].scriptPubKey.hex")"
            break
        fi
    fi
    ((idx++))
done < <(echo "$rawtx" | jq -r ".vout[].scriptPubKey.addresses[0]")
#done < <(echo "$rawtx" | jq_btc_float ".vout[].value")
if [ "$prev_pubkey" == "" ]; then
    echoerr "$rawtx"
    echoerr "FATAL: Can't find the right vout in the first transaction, please fill a bug report!"
    exit 1
fi

# Prepare and sign rest of transactions
echo "Preparing rest of transactions..."
signedtxes=()
for i in $(seq 1 $(( $hops - 1 ))); do
    send_amount=$(bc_float_calc "$send_amount - $single_ricochet_tx_fee")
    echo -n "$i: ${ricochet_addresses[$(( $i - 1 ))]} -> ${ricochet_addresses[$i]} ($send_amount) - "
    rawtx=$(call_bitcoin_cli createrawtransaction "[{\"txid\":\"$txid\",\"vout\":$vout_idx}]" "{\"${ricochet_addresses[$i]}\":$send_amount}")
    privkey=$(call_bitcoin_cli dumpprivkey "${ricochet_addresses[$(( $i - 1 ))]}")
    signedtx="$(signrawtransactionwithkey "$rawtx" "[\"$privkey\"]" "[{\"txid\":\"$txid\",\"vout\":$vout_idx,\"scriptPubKey\":\"$prev_pubkey\",\"amount\":$send_amount}]")"
    decodedtx="$(call_bitcoin_cli decoderawtransaction "$signedtx")"
    txid="$(echo "$decodedtx" | jq -r ".txid")"
    signedtxes+=("$signedtx")
    vout_idx=0
    prev_pubkey="$(echo "$decodedtx" | jq -r ".vout[].scriptPubKey.hex")"
    echo "$txid"
done

#printf '%s\n' "${signedtxes[@]}"

PREPARE_DURATION="$(echo "$(date +%s.%N) - $PREPARE_START" | bc)"
LANG=POSIX printf "Initial transaction preparing took %.6f seconds\n" $PREPARE_DURATION

# Broadcast transactions with delays
echo "Sending transactions..."
for i in $(seq 1 $(( $hops - 1 ))); do
    random_delay=$(( $RANDOM % ($sleeptime_max - $sleeptime_min) + $sleeptime_min ))
    echo "Sleeping for $random_delay seconds"
    sleep $random_delay
    echo "$i: $(call_bitcoin_cli sendrawtransaction "${signedtxes[$(( $i - 1 ))]}")"
done

