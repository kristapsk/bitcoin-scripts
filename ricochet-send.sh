#! /bin/bash

. $(dirname $0)/inc.common.sh

if [ "$2" == "" ]; then
    echo "Usage: $(basename $0) [options] amount address [hops] [fee] [sleeptime_min] [sleeptime_max]"
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
if [ "$fee" == "0.00000000" ]; then
    fee=0.00001000
fi

echo "Ricocheting $amount BTC to $address via $hops hops using $fee fee per KB"

ricochet_addresses=()
for i in $(seq 1 $(( $hops - 1 ))); do
    ricochet_addresses+=("$(call_bitcoin_cli getnewaddress)")
done
ricochet_addresses+=("$address")

# FixMe: TX size may vary depending on input and output address types
ricochet_tx_size=192
single_ricochet_tx_fee=$(bc_float_calc "$ricochet_tx_size * $fee * 0.001")
ricochet_fees=$(bc_float_calc "($hops - 1) * $single_ricochet_tx_fee")
send_amount=$(bc_float_calc "$amount + $ricochet_fees")

#echo "Richochet addresses: ${ricochet_addresses[@]}"

echo "(wallet) -> ${ricochet_addresses[0]} ($send_amount)"
call_bitcoin_cli settxfee $fee
txid=$(call_bitcoin_cli sendtoaddress ${ricochet_addresses[0]} $send_amount)
rawtx=$(show_tx_by_id $txid)
#echo "$rawtx"
vout_idx=""
idx=0
while read value; do
    if [ "$value" == "$send_amount" ]; then
        vout_idx=$idx
        break
    fi
    ((idx++))
done < <(echo "$rawtx" | jq_btc_float ".vout[].value")
if [ "$vout_idx" == "" ]; then
    echoerr "$rawtx"
    echoerr "FATAL: Can't find the right vout in the first transaction, please fill a bug report!"
    exit 1
fi

for i in $(seq 1 $(( $hops - 1 ))); do
    random_delay=$(( $RANDOM % ($sleeptime_max - $sleeptime_min) + $sleeptime_min ))
    echo "Sleeping for $random_delay seconds"
    sleep $random_delay
    send_amount=$(bc_float_calc "$send_amount - $single_ricochet_tx_fee")
    echo "${ricochet_addresses[$(( $i - 1 ))]} -> ${ricochet_addresses[$i]} ($send_amount)"
    rawtx=$(call_bitcoin_cli createrawtransaction "[{\"txid\":\"$txid\",\"vout\":$vout_idx}]" "{\"${ricochet_addresses[$i]}\":$send_amount}")
    signedtx=$(call_bitcoin_cli signrawtransaction "$rawtx" | jq -r ".hex")
    txid=$(call_bitcoin_cli sendrawtransaction $signedtx)
    vout_idx=0
done

