#! /bin/bash

. $(dirname $0)/inc.common.sh

if [ "$3" == "" ]; then
    echo "Usage: $(basename $0) [options] amount address1 address2..."
    exit
fi

# Some configs, names match of those of JoinMarket and values are JM defaults

# Estimated blocks to confirm when calculating TX fees
tx_fees=3
# Abort if TX fee per KB is above this number
absurd_fee_per_kb=150000
# Minimum number of confirmations for UTXO's to be usable
taker_utxo_age=5
# Minimum amount for UTXO's to be usable (percentage from send amount)
taker_utxo_amtpercent=20

# End of configs


amount=$(echo "$1" | btc_amount_format)
shift

min_utxo_amount=$(bc_float_calc "$amount * $taker_utxo_amtpercent / 100")
fee=$($(dirname $0)/estimatesmartfee.sh $bitcoin_cli_options $tx_fees)
if is_btc_gte "$fee" "$(bc_float_calc "$absurd_fee_per_kb * 0.00000001")"; then
    echo -n "Estimated fee per KB ($fee) is greater than absurd value: "
    echo "$(bc_float_calc "$absurd_fee_per_kb * 0.00000001"), quitting."
    exit 1
fi
echo "Using fee $fee per KB"

recipients=()
p2pkh_recipient_count=0
p2sh_recipient_count=0

while (( ${#} > 0 )); do
    address=$1
    if ! is_valid_bitcoin_address $address; then
        echo "Invalid address $address"
        exit 1
    fi
    recipients+=("$address")
    if is_p2pkh_bitcoin_address $address; then
        ((p2pkh_recipient_count++))
    else
        ((p2sh_recipient_count++))
    fi
    shift
done

if (( $p2pkh_recipient_count > 1 )) && (( $p2sh_recipient_count > 1 )); then
    echo "Only one recipient can be a different kind! (P2PKH or P2SH)"
    exit 2
fi

(( $p2pkh_recipient_count > $p2sh_recipient_count )) && \
    input_type="p2pkh" || input_type="p2sh"

if [ "$input_type" != "p2pkh" ]; then
    echo "TODO: P2SH fake coinjoin isn't yet working"
    exit 1
fi

utxo="$(call_bitcoin_cli listunspent $taker_utxo_age 999999)"
readarray -t utxo_txids < <( echo "$utxo" | jq -r ".[].txid" )
readarray -t utxo_vouts < <( echo "$utxo" | jq -r ".[].vout" )
readarray -t utxo_addresses < <( echo "$utxo" | jq -r ".[].address" )
readarray -t utxo_amounts < <( echo "$utxo" | jq_btc_float ".[].amount" )

# Filter out unwanted input address types
# Also ignore UTXO's with address reuse, JoinMarket normally don't have them
# And check amounts to be above taker_utxo_amtpercent
utxo_reused_addresses="$(printf '%s ' "${utxo_addresses[@]}" | \
    awk '!($0 in seen){seen[$0];next} 1')"
utxo_txids_filtered=()
utxo_vouts_filtered=()
utxo_addresses_filtered=()
utxo_amounts_filtered=()
for i in $(seq 0 $(( ${#utxo_addresses[@]} - 1 ))); do
    if \
        eval "is_${input_type}_bitcoin_address ${utxo_addresses[$i]}" && \
        grep -qsv "${utxo_addresses[$i]}" <<< "$utxo_reused_addresses" && \
        is_btc_gte "${utxo_amounts[$i]}" "$min_utxo_amount";
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

printf '%s\n' "${utxo_addresses_filtered[@]}"
printf '%s\n' "${utxo_amounts_filtered[@]}"
echo "${#utxo_addresses_filtered[@]}"

# Dumb coin selection for now
# Just go through all the inputs, and for each recipient add them together
# until total amount is send amount + dust threshold + some fees(?)
# This could be improved in future, JoinMarket do better.
# Also in the process we create change addresses for TX.
# There we also check returned address type, does it match.
# If P2PKH is returned but P2SH is required, try "addwitnessaddress".

# Calculate fees, TX input/output bytes, etc here

mixdepth=${#recipients[@]}

# Simpler way
# First destinations assume as makers
# Last one is taker, pays all the fees

# Select "maker" inputs
maker_utxo_idxs=()
utxo_idx=0
maker_change_outputs=()
maker_change_amounts=()
total_maker_fees=0
for i in $(seq 0 $(( $mixdepth - 2 ))); do
    current_mixdepth_inputs_sum=0
    while
        (( $utxo_idx < ${#utxo_addresses_filtered[@]} )) && \
        is_btc_gte "$amount" "$current_mixdepth_inputs_sum";
    do
        current_mixdepth_inputs_sum=$(bc_float_calc "$current_mixdepth_inputs_sum + ${utxo_amounts_filtered[$utxo_idx]}")
        maker_utxo_idxs+=("$utxo_idx")
        ((utxo_idx++))
    done
    if ! is_btc_gte "$amount" "$current_mixdepth_inputs_sum"; then
        # Add some simple random "maker" fee for now (800 .. 1200)
        makerfee="$(bc_float_calc "$(( $RANDOM % 400 + 800 )) * 0.00000001")"
        if [ "$input_type" == "p2sh" ]; then
            maker_change_outputs+=("$(getnewaddress_p2wsh)")
            maker_change_outputs+=("$(getnewaddress_p2wsh)")
        else
            maker_change_outputs+=("$(getnewaddress_p2pkh)")
            maker_change_outputs+=("$(getnewaddress_p2pkh)")
        fi
        maker_change_amounts+=("$amount")
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

if is_btc_gte "$amount" "$current_mixdepth_inputs_sum"; then
    echo "Not enough good inputs, aborting."
    exit 1
fi

# Calculate fees
# Currently assume we will have two outputs per each input
# May not be true for some rare cases, but this way it's easer
# In those rare cases you will pay some extra satoshis to miners
tx_size=$(( $TX_FIXED_SIZE + $p2pkh_recipient_count * $TX_P2PKH_OUT_SIZE * 2 + $p2sh_recipient_count * $TX_P2SH_OUT_SIZE * 2 ))
if [ "$input_type" == "p2pkh" ]; then
    tx_size=$(( $tx_size + ${#maker_utxo_idxs[@]} * $TX_P2PKH_IN_SIZE ))
else
    tx_size=$(( $tx_size + ${#maker_utxo_idxs[@]} * $TX_P2WSH_IN_SIZE ))
fi
echo "tx_size = $tx_size"

# Select "taker" inputs
taker_amount=$(bc_float_calc "$amount + $tx_size * $fee * 0.001")
echo "taker_amount = $taker_amount"
taker_amount=$(bc_float_calc "$amount + $tx_size * $fee * 0.001 + $total_maker_fees")
echo "taker_amount = $taker_amount"

taker_utxo_idxs=()
current_mixdepth_inputs_sum=0
taker_change_outputs=()
taker_change_amounts=()
while
    (( $utxo_idx < ${#utxo_addresses_filtered[@]} )) && \
    is_btc_gte "$taker_amount" "$current_mixdepth_inputs_sum";
do
    current_mixdepth_inputs_sum=$(bc_float_calc "$current_mixdepth_inputs_sum + ${utxo_amounts_filtered[$utxo_idx]}")
    taker_utxo_idxs+=("$utxo_idx")
    ((utxo_idx++))
    if [ "$input_type" == "p2pkh" ]; then
        tx_size=$(( $tx_size + $TX_P2PKH_IN_SIZE ))
        taker_amount=$(bc_float_calc "$taker_amount + $TX_P2PKH_IN_SIZE * $fee * 0.001")
    else
        tx_size=$(( $tx_size + $TX_P2WSH_IN_SIZE ))
        taker_amount=$(bc_float_calc "$taker_amount + $TX_P2WSH_IN_SIZE * $fee * 0.001")
    fi
done

echo "Calculated taker inputs:"
for i in $(seq 0 $(( ${#taker_utxo_idxs[@]} - 1 ))); do
    echo "${taker_utxo_idxs[$i]}: ${utxo_amounts_filtered[${taker_utxo_idxs[$i]}]} ${utxo_addresses_filtered[${taker_utxo_idxs[$i]}]}"
done

if is_btc_gte "$taker_amount" "$current_mixdepth_inputs_sum"; then
    echo "Not enough good inputs, aborting."
    exit 1
fi

if [ "$input_type" == "p2sh" ]; then
    taker_change_outputs+=("$(getnewaddress_p2wsh)")
    taker_change_outputs+=("$(getnewaddress_p2wsh)")
else
    taker_change_outputs+=("$(getnewaddress_p2pkh)")
    taker_change_outputs+=("$(getnewaddress_p2pkh)")
fi
taker_change_amounts+=("$amount")
taker_change_amounts+=("$(bc_float_calc "$current_mixdepth_inputs_sum - $taker_amount")")

echo "Calculated taker outputs:"
for i in $(seq 0 $(( ${#taker_change_amounts[@]} - 1 ))); do
    echo "$i: ${taker_change_amounts[$i]} ${taker_change_outputs[$i]}"
done

echo "tx_size = $tx_size"
echo "TX fee: $(bc_float_calc "$tx_size * $fee * 0.001")"

# DO TX

rawtx_inputs="["
needs_comma=0
for i in $(seq 0 $(( ${#maker_utxo_idxs[@]} - 1 ))); do
    if [ "$needs_comma" == "1" ]; then
        rawtx_inputs="$rawtx_inputs,"
    fi
    rawtx_inputs="$rawtx_inputs{\"txid\":\"${utxo_txids_filtered[${maker_utxo_idxs[$i]}]}\",\"vout\":${utxo_vouts_filtered[${maker_utxo_idxs[$i]}]}}"
    needs_comma=1
done
for i in $(seq 0 $(( ${#taker_utxo_idxs[@]} - 1 ))); do
    rawtx_inputs="$rawtx_inputs,{\"txid\":\"${utxo_txids_filtered[${taker_utxo_idxs[$i]}]}\",\"vout\":${utxo_vouts_filtered[${taker_utxo_idxs[$i]}]}}"
done
rawtx_inputs="$rawtx_inputs]"
echo "rawtx_inputs: $rawtx_inputs"

rawtx_outputs="{"
needs_comma=0
for i in $(seq 0 $(( ${#maker_change_amounts[@]} - 1 ))); do
    if [ "$needs_comma" == "1" ]; then
        rawtx_outputs="$rawtx_outputs,"
    fi
    rawtx_outputs="$rawtx_outputs\"${maker_change_outputs[$i]}\":\"${maker_change_amounts[$i]}\""
    needs_comma=1
done
for i in $(seq 0 $(( ${#taker_change_amounts[@]} - 1 ))); do
    rawtx_outputs="$rawtx_outputs,\"${taker_change_outputs[$i]}\":\"${taker_change_amounts[$i]}\""
done
rawtx_outputs="$rawtx_outputs}"
echo "rawtx_outputs: $rawtx_outputs"

rawtx=$(call_bitcoin_cli createrawtransaction "$rawtx_inputs" "$rawtx_outputs")
echo "$(call_bitcoin_cli decoderawtransaction "$rawtx")"

read -p "Sign and broadcast this transaction? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    signedtx=$(call_bitcoin_cli signrawtransaction "$rawtx" | jq -r ".hex")
    txid=$(call_bitcoin_cli sendrawtransaction $signedtx)
    echo "Sent transaction $txid"
fi

