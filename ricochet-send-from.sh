#! /bin/bash

. $(dirname $0)/inc.common.sh

if [ "$2" == "" ]; then
    echo "Usage: $(basename $0) [options] source_address destination_address [hops] [fee] [sleeptime_min] [sleeptime_max]"
    exit
fi

source_address=$1
destination_address=$2
if
    ! is_valid_bitcoin_address $source_address || \
    ! is_valid_bitcoin_address $destination_address; 
then
    echo "Invalid Bitcoin address $address"
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

utxo="$(call_bitcoin_cli listunspent 0 999999 '[]' false)"
readarray -t utxo_txids < <( echo "$utxo" | jq -r ".[].txid" )
readarray -t utxo_vouts < <( echo "$utxo" | jq -r ".[].vout" )
readarray -t utxo_addresses < <( echo "$utxo" | jq -r ".[].address" )
readarray -t utxo_amounts < <( echo "$utxo" | jq_btc_float ".[].amount" )

# Find UTXO's belonging to source_address
utxo_txids_filtered=()
utxo_vouts_filtered=()
send_amount=0
for i in $(seq 0 $(( ${#utxo_addresses[@]} - 1 ))); do
    if [ "${utxo_addresses[$i]}" == "$source_address" ]; then
        utxo_txids_filtered+=("${utxo_txids[$i]}")
        utxo_vouts_filtered+=("${utxo_vouts[$i]}")
        send_amount=$(bc_float_calc "$send_amount + ${utxo_amounts[$i]}")
    fi
done

if [ "${#utxo_txids_filtered[@]}" == "0" ]; then
    echo "No matching inputs belonging to address $source_address"
    exit 2
fi

echo "Ricocheting from $source_address ($send_amount BTC) to $destination_address via $hops hops using $fee fee per KB"
read -p "Is this ok? " -n 1 -r
echo

if ! [[ $REPLY =~ ^[Yy]$ ]]; then
    echo NOT
    exit
fi

ricochet_addresses=()
# add destination first, we will iterate in reverse order (see tac in for below)
ricochet_addresses+=("$destination_address")
for i in $(seq 1 $(( $hops - 1 ))); do
    ricochet_addresses+=("$(call_bitcoin_cli getnewaddress)")
done

source_address_type=$(get_bitcoin_address_type "$source_address")
ricochet_address_type=$(get_bitcoin_address_type "${ricochet_addresses[0]}")
destination_address_type=$(get_bitcoin_address_type "$destination_address")

#echo "Richochet addresses: ${ricochet_addresses[@]}"

echo "$source_address -> ${ricochet_addresses[$(( $hops - 1 ))]} ($send_amount)"

# Calculate TX fee and build first transaction
if [ "$source_address_type" == "p2pkh" ]; then
    if [ "$ricochet_address_type" == "p2pkh" ]; then
        tx_vsize=$(calc_tx_vsize ${#utxo_txids_filtered[@]} 0 1 0)
    else
        tx_vsize=$(calc_tx_vsize ${#utxo_txids_filtered[@]} 0 0 1)
    fi
else
    if [ "$ricochet_address_type" == "p2pkh" ]; then
        tx_vsize=$(calc_tx_vsize 0 ${#utxo_txids_filtered[@]} 1 0)
    else
        tx_vsize=$(calc_tx_vsize 0 ${#utxo_txids_filtered[@]} 0 1)
    fi
fi
rawtx_inputs="["
needs_comma=0
for i in $(seq 0 $(( ${#utxo_txids_filtered[@]} - 1 )) ); do
    if [ "$needs_comma" == "1" ]; then
        rawtx_inputs="$rawtx_inputs,"
    fi
    rawtx_inputs="$rawtx_inputs{\"txid\":\"${utxo_txids_filtered[$i]}\",\"vout\":${utxo_vouts_filtered[$i]}}"
    needs_comma=1
done
rawtx_inputs="$rawtx_inputs]"
send_amount=$(bc_float_calc "$send_amount - $(bc_float_calc "$tx_vsize * $fee * 0.001")")
rawtx=$(call_bitcoin_cli createrawtransaction "$rawtx_inputs" "{\"${ricochet_addresses[$(( $hops - 1 ))]}\":$send_amount}")
signedtx=$(call_bitcoin_cli signrawtransaction "$rawtx" | jq -r ".hex")
txid=$(call_bitcoin_cli sendrawtransaction $signedtx)

# Do the rest of the transactions

for i in $(seq 1 $(( $hops - 1 )) | tac); do
    random_delay=$(( $RANDOM % ($sleeptime_max - $sleeptime_min) + $sleeptime_min ))
    echo "Sleeping for $random_delay seconds"
    sleep $random_delay

    if [ "$i" == "1" ]; then
        output_address_type=$destination_address_type
    else
        output_address_type=$ricochet_address_type
    fi
    if [ "$ricochet_address_type" == "p2pkh" ]; then
        if [ "$output_address_type" == "p2pkh" ]; then
            tx_vsize=$(calc_tx_vsize 1 0 1 0)
        else
            tx_vsize=$(calc_tx_vsize 1 0 0 1)
        fi
    else
        if [ "$output_address_type" == "p2pkh" ]; then
            tx_vsize=$(calc_tx_vsize 0 1 1 0)
        else
            tx_vsize=$(calc_tx_vsize 0 1 0 1)
        fi
    fi

    send_amount=$(bc_float_calc "$send_amount - $(bc_float_calc "$tx_vsize * $fee * 0.001")")
    echo "${ricochet_addresses[$i]} -> ${ricochet_addresses[$(( $i - 1 ))]} ($send_amount)"
    rawtx=$(call_bitcoin_cli createrawtransaction "[{\"txid\":\"$txid\",\"vout\":0}]" "{\"${ricochet_addresses[$(( $i - 1 ))]}\":$send_amount}")
    signedtx=$(call_bitcoin_cli signrawtransaction "$rawtx" | jq -r ".hex")
    txid=$(call_bitcoin_cli sendrawtransaction $signedtx)
done

