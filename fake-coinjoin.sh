#! /bin/bash

. $(dirname $0)/inc.common.sh

if [ "$3" == "" ]; then
    echo "Usage: $(basename $0) [options] amount address1 address2..."
    echo "Where:"
    echo "  amount              - amount to send in BTC"
    echo "  address...          - destination addresses (2 or more)"
    exit
fi

# Some configs, names match of those of JoinMarket and values are JM defaults

# Estimated blocks to confirm when calculating TX fees
tx_fees=3
# Abort if TX fee per KB is above this number (satoshis)
absurd_fee_per_kb=150000
# Minimum number of confirmations for UTXO's to be usable
taker_utxo_age=5
# Coin selection ("merge") algorithm.
# Not the same as JM algos currently.
# "default" is a dumb coin selection, using random order.
# "greediest" is for rapid dust sweeping, ordering UTXO's from the smallest upwards.
merge_algorithm=default

# Dust threshold in satoshis, don't create smaller outputs
DUST_THRESHOLD=27300

# End of configs


amount=$(echo "$1" | btc_amount_format)
shift

fee=$($(dirname $0)/estimatesmartfee.sh $bitcoin_cli_options $tx_fees)
if [ "$fee" == "" ]; then
    echoerr "estimatesmartfee failed"
    exit 1
fi
minrelayfee=$(call_bitcoin_cli getnetworkinfo | jq_btc_float ".relayfee")
if is_btc_lt "$fee" "$minrelayfee"; then
    echo "Fee $fee is below minimum relay fee, raising to $minrelayfee"
    fee=$minrelayfee
fi
if is_btc_gte "$fee" "$(bc_float_calc "$absurd_fee_per_kb * 0.00000001")"; then
    echoerr -n "Estimated fee per KB ($fee) is greater than absurd value: "
    echoerr "$(bc_float_calc "$absurd_fee_per_kb * 0.00000001"), quitting."
    exit 1
fi
echo "Using fee $fee per KB"

recipients=()
p2pkh_recipient_count=0
p2sh_recipient_count=0
bech32_recipient_count=0

while (( ${#} > 0 )); do
    address=$1
    if ! is_valid_bitcoin_address $address; then
        echoerr "Invalid address $address"
        exit 1
    fi
    recipients+=("$address")
    if is_p2pkh_bitcoin_address $address; then
        ((p2pkh_recipient_count++))
    elif is_p2sh_bitcoin_address $address; then
        ((p2sh_recipient_count++))
    else
        ((bech32_recipient_count++))
    fi
    shift
done

if (( $p2pkh_recipient_count > 1 )) && (( $p2sh_recipient_count > 1 )); then
    echoerr "Only one recipient can be a different kind! (P2PKH or P2SH)"
    exit 2
fi

if (( $bech32_recipient_count > 1 )); then
    echoerr "Only one bech32 recipient is supported currently!"
    exit 2
fi

if (( $bech32_recipient_count > 0 )) && (( $p2pkh_recipient_count > 0 )); then
    echoerr "Bech32 recipient can be combined only with P2SH recipients!"
    exit 2
fi

if (( ${#recipients[@]} > $(( $TX_OUTPUTS_MAX / 2 )) )); then
    echoerr "More than $(( $TX_OUTPUTS_MAX / 2 )) recipients aren't supported!"
    exit 3
fi

(( $p2pkh_recipient_count > $p2sh_recipient_count )) && \
    input_type="p2pkh" || input_type="p2sh_segwit"

echo "Recipients: ${recipients[@]}"
echo "input_type: $input_type"

function select_default()
{
    jq -c "" | shuf | jq ""
}

function select_greediest()
{
    jq -s "sort_by(.amount) | .[]"
}

utxo="$(call_bitcoin_cli listunspent $taker_utxo_age 999999 "[]" false | jq ".[] | select(.spendable)")"
if [ "$merge_algorithm" == "greediest" ]; then
    utxo="$(echo "$utxo" | select_greediest)"
else
    utxo="$(echo "$utxo" | select_default)"
fi

readarray -t utxo_txids < <( echo "$utxo" | jq -r ".txid" )
readarray -t utxo_vouts < <( echo "$utxo" | jq -r ".vout" )
readarray -t utxo_addresses < <( echo "$utxo" | jq -r ".address" )
readarray -t utxo_amounts < <( echo "$utxo" | jq_btc_float ".amount" )

# Filter out unwanted input address types
# Also ignore UTXO's with address reuse, JoinMarket normally don't have them
utxo_reused_addresses="$(printf '%s ' "${utxo_addresses[@]}" | \
    awk '!($0 in seen){seen[$0];next} 1')"
utxo_txids_filtered=()
utxo_vouts_filtered=()
utxo_addresses_filtered=()
utxo_amounts_filtered=()
for i in $(seq 0 $(( ${#utxo_addresses[@]} - 1 ))); do
    if \
        eval "is_${input_type}_bitcoin_address ${utxo_addresses[$i]}" && \
        grep -qsv "${utxo_addresses[$i]}" <<< "$utxo_reused_addresses"
    then
        utxo_txids_filtered+=("${utxo_txids[$i]}")
        utxo_vouts_filtered+=("${utxo_vouts[$i]}")
        utxo_addresses_filtered+=("${utxo_addresses[$i]}")
        utxo_amounts_filtered+=("${utxo_amounts[$i]}")
    fi
done
unset utxo_txids
unset utxo_vouts
unset utxo_addresses
unset utxo_amounts

#printf '%s\n' "${utxo_addresses_filtered[@]}"
#printf '%s\n' "${utxo_amounts_filtered[@]}"
#echo "${#utxo_addresses_filtered[@]}"

# Calculate fees, TX input/output bytes, etc here

mixdepth=${#recipients[@]}

# Select "maker" inputs
maker_utxo_idxs=()
utxo_idx=0
maker_change_outputs=()
maker_change_amounts=()
total_maker_fees=0
# minimum taker amount must be above amount + dust
minimum_taker_amount="$(bc_float_calc "$amount + ($DUST_THRESHOLD * 0.00000001) + 0.00000001")"
for i in $(seq 0 $(( $mixdepth - 2 ))); do
    current_mixdepth_inputs_sum=0
    maker_used_txids=()
    while
        (( $utxo_idx < ${#utxo_addresses_filtered[@]} )) && \
        is_btc_gte "$minimum_taker_amount" "$current_mixdepth_inputs_sum";
    do
        # Stonewall rule: Utxos resulting from the same transaction are never used together in a same set.
        if ! grep -qs "${utxo_txids_filtered[$utxo_idx]}" <<< "${maker_used_txids[@]}"; then
            current_mixdepth_inputs_sum=$(bc_float_calc "$current_mixdepth_inputs_sum + ${utxo_amounts_filtered[$utxo_idx]}")
            maker_utxo_idxs+=("$utxo_idx")
            maker_used_txids+=("${utxo_txids_filtered[$utxo_idx]}")
#        else
#            echo "Skipping utxo_idx $utxo_idx for a maker, as txid ${utxo_txids_filtered[$utxo_idx]} already used"
        fi
        ((utxo_idx++))
    done
    if ! is_btc_gte "$minimum_taker_amount" "$current_mixdepth_inputs_sum"; then
        # Add some simple random "maker" fee for now (800 .. 1200)
        makerfee="$(bc_float_calc "$(( $RANDOM % 400 + 800 )) * 0.00000001")"
        maker_change_outputs+=("$(eval "getnewaddress_$input_type")")
        maker_change_amounts+=("$(bc_float_calc "$current_mixdepth_inputs_sum - $amount + $makerfee")")
        total_maker_fees="$(bc_float_calc "$total_maker_fees + $makerfee")"
    fi
done

echo "Selected maker inputs:"
for i in $(seq 0 $(( ${#maker_utxo_idxs[@]} - 1 ))); do
    echo "${maker_utxo_idxs[$i]}: ${utxo_amounts_filtered[${maker_utxo_idxs[$i]}]} ${utxo_addresses_filtered[${maker_utxo_idxs[$i]}]}"
done

echo "Calculated maker outputs:"
for i in $(seq 0 $(( ${#maker_change_amounts[@]} - 1 ))); do
    echo "$i: ${maker_change_amounts[$i]} ${maker_change_outputs[$i]}"
done

if is_btc_gte "$minimum_taker_amount" "$current_mixdepth_inputs_sum"; then
    echoerr "Not enough good inputs, aborting."
    exit 1
fi

# Calculate fees
# https://bitcoincore.org/en/segwit_wallet_dev/#transaction-fee-estimation

# Recipients
tx_vsize=$(( $p2pkh_recipient_count * $TX_P2PKH_OUT_SIZE ))
tx_vsize=$(( $tx_vsize + $p2sh_recipient_count * $TX_P2SH_OUT_SIZE ))
tx_vsize=$(( $tx_vsize + $bech32_recipient_count * $TX_P2WPKH_OUT_SIZE ))
# Fixed size + "maker" inputs + "maker" change outputs
if [ "$input_type" == "p2pkh" ]; then
    tx_vsize=$(( $tx_vsize + $TX_FIXED_SIZE ))
    tx_vsize=$(( $tx_vsize + ${#maker_utxo_idxs[@]} * $TX_P2PKH_IN_SIZE ))
    tx_vsize=$(( $tx_vsize + ${#maker_change_outputs[@]} * $TX_P2PKH_OUT_SIZE ))
else
    tx_vsize=$(( $tx_vsize * 4 ))
    tx_vsize=$(( $tx_vsize + $TX_FIXED_SIZE * 3 + $TX_SEGWIT_FIXED_SIZE ))
    # P2SH segwit maker inputs
    tx_vsize=$(( $tx_vsize + ${#maker_utxo_idxs[@]} * ( $TX_P2SH_SEGWIT_IN_SIZE * 4 + $TX_P2SH_SEGWIT_WITNESS_SIZE * 3 ) ))
    # P2SH maker change outputs (recipient outputs already calculated above)
    tx_vsize=$(( $tx_vsize + ${#maker_change_outputs[@]} * $TX_P2SH_OUT_SIZE * 4 ))
    # real size
    tx_vsize=$(( ($tx_vsize + 1) / 4 ))
fi

# Calculate taker fee
taker_amount=$(bc_float_calc "$amount + $tx_vsize * $fee * 0.001 + $total_maker_fees")
echo "taker_amount = $taker_amount"

# Select "taker" inputs

taker_utxo_idxs=()
current_mixdepth_inputs_sum=0
taker_used_txids=()
while
    (( $utxo_idx < ${#utxo_addresses_filtered[@]} )) && \
    is_btc_gte "$taker_amount" "$current_mixdepth_inputs_sum";
do
    # Stonewall rule: Utxos resulting from the same transaction are never used together in a same set.
    if ! grep -qs "${utxo_txids_filtered[$utxo_idx]}" <<< "${taker_used_txids[@]}"; then
        current_mixdepth_inputs_sum=$(bc_float_calc "$current_mixdepth_inputs_sum + ${utxo_amounts_filtered[$utxo_idx]}")
        taker_utxo_idxs+=("$utxo_idx")
        taker_used_txids+=("${utxo_txids_filtered[$utxo_idx]}")
#    else
#        echo "Skipping utxo_idx $utxo_idx for a taker, as txid ${utxo_txids_filtered[$utxo_idx]} already used"
    fi
    ((utxo_idx++))
    if [ "$input_type" == "p2pkh" ]; then
        tx_vsize=$(( $tx_vsize + $TX_P2PKH_IN_SIZE ))
        taker_amount=$(bc_float_calc "$taker_amount + $TX_P2PKH_IN_SIZE * $fee * 0.001")
    else
        additional_tx_vsize=$(( $TX_P2SH_SEGWIT_IN_SIZE * 4 + $TX_P2SH_SEGWIT_WITNESS_SIZE * 3 ))
        additional_tx_vsize=$(( ($additional_tx_vsize + 1) / 4 ))
        tx_vsize=$(( $tx_vsize + $additional_tx_vsize ))
        taker_amount=$(bc_float_calc "$taker_amount + $additional_tx_vsize * $fee * 0.001")
    fi
done

echo "Calculated taker inputs:"
for i in $(seq 0 $(( ${#taker_utxo_idxs[@]} - 1 ))); do
    echo "${taker_utxo_idxs[$i]}: ${utxo_amounts_filtered[${taker_utxo_idxs[$i]}]} ${utxo_addresses_filtered[${taker_utxo_idxs[$i]}]}"
done

if is_btc_gte "$taker_amount" "$current_mixdepth_inputs_sum"; then
    echoerr "Not enough good inputs, aborting."
    exit 1
fi

taker_change_amount="$(bc_float_calc "$current_mixdepth_inputs_sum - $taker_amount")"
if [ "$input_type" == "p2pkh" ]; then
    taker_change_amount="$(bc_float_calc "$taker_change_amount - ($TX_P2PKH_OUT_SIZE * 0.00000001)")"
else
    taker_change_amount="$(bc_float_calc "$taker_change_amount - ($TX_P2SH_OUT_SIZE * 0.00000001)")"
fi
if is_btc_gte "$taker_change_amount" "$(bc_float_calc "$DUST_THRESHOLD * 0.00000001")"; then
    taker_change_output="$(eval "getnewaddress_$input_type")"
    if [ "$input_type" == "p2pkh" ]; then
        tx_vsize=$(( $tx_vsize + $TX_P2PKH_OUT_SIZE ))
    else
        tx_vsize=$(( $tx_vsize + $TX_P2SH_OUT_SIZE ))
    fi
else
    echo "Not creating dust amount taker change output, adding to the fees."
fi

if [ "$taker_change_output" != "" ]; then
    echo "Calculated taker outputs:"
    echo "0: $taker_change_amount $taker_change_output"
fi

echo "tx_vsize = $tx_vsize"
echo "Calculated TX fee: $(bc_float_calc "$tx_vsize * $fee * 0.001")"

# Join all inputs and outputs together so we can randomize order

input_utxo_txids=()
input_utxo_vouts=()
output_addresses=()
output_amounts=()

for i in $(seq 0 $(( ${#maker_utxo_idxs[@]} - 1 ))); do
    input_utxo_txids+=("${utxo_txids_filtered[${maker_utxo_idxs[$i]}]}")
    input_utxo_vouts+=("${utxo_vouts_filtered[${maker_utxo_idxs[$i]}]}")
done
for i in $(seq 0 $(( ${#taker_utxo_idxs[@]} - 1 ))); do
    input_utxo_txids+=("${utxo_txids_filtered[${taker_utxo_idxs[$i]}]}")
    input_utxo_vouts+=("${utxo_vouts_filtered[${taker_utxo_idxs[$i]}]}")
done

for i in $(seq 0 $(( ${#recipients[@]} - 1 ))); do
    output_addresses+=("${recipients[$i]}")
    output_amounts+=("$amount")
done
for i in $(seq 0 $(( ${#maker_change_amounts[@]} - 1 ))); do
    output_addresses+=("${maker_change_outputs[$i]}")
    output_amounts+=("${maker_change_amounts[$i]}")
done
if [ "$taker_change_output" != "" ]; then
    output_addresses+=("$taker_change_output")
    output_amounts+=("$taker_change_amount")
fi

# Randomize order
input_it=$(seq 0 $(( ${#input_utxo_txids[@]} - 1 )) | shuf)
output_it=$(seq 0 $(( ${#output_addresses[@]} - 1 )) | shuf)

# DO TX

rawtx_inputs="["
needs_comma=0
for i in $input_it; do
    if [ "$needs_comma" == "1" ]; then
        rawtx_inputs="$rawtx_inputs,"
    fi
    rawtx_inputs="$rawtx_inputs{\"txid\":\"${input_utxo_txids[$i]}\",\"vout\":${input_utxo_vouts[$i]}}"
    needs_comma=1
done
rawtx_inputs="$rawtx_inputs]"
echo "rawtx_inputs: $rawtx_inputs"

rawtx_outputs="{"
needs_comma=0
for i in $output_it; do
    if [ "$needs_comma" == "1" ]; then
        rawtx_outputs="$rawtx_outputs,"
    fi
    rawtx_outputs="$rawtx_outputs\"${output_addresses[$i]}\":\"${output_amounts[$i]}\""
    needs_comma=1
done
rawtx_outputs="$rawtx_outputs}"
echo "rawtx_outputs: $rawtx_outputs"

rawtx=$(call_bitcoin_cli createrawtransaction "$rawtx_inputs" "$rawtx_outputs")
echo "Raw transaction: $rawtx"
call_bitcoin_cli decoderawtransaction "$rawtx"

read -p "Sign and broadcast this transaction? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    signedtx=$(signrawtransactionwithwallet "$rawtx")
    txid=$(call_bitcoin_cli sendrawtransaction $signedtx)
    echo "Sent transaction $txid"
fi

