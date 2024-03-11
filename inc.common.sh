# shellcheck disable=SC2148

bitcoin_cli="bitcoin-cli"
bitcoin_cli_options=""
testnet=0
has_rpcwallet=0

# assume all first parameters beginning with dash are bitcoin-cli options
while (( ${#} > 0 )) && [[ ${1:0:1} == "-" ]]; do
    bitcoin_cli_options="$bitcoin_cli_options $1"
    if [ "$1" == "-regtest" ] || [ "$1" == "-testnet" ] || [ "$1" == "-signet" ]; then
        testnet=1
    elif [ "${1:0:11}" == "-rpcwallet=" ]; then
        has_rpcwallet=1
    fi
    shift
done
bitcoin_cli="$bitcoin_cli$bitcoin_cli_options"

# Some constants
# We assume no more than 253 TX inputs or outputs
TX_INPUTS_MAX=253
TX_OUTPUTS_MAX=253
TX_FIXED_SIZE=10
TX_SEGWIT_FIXED_SIZE=11
TX_P2PKH_IN_SIZE=148
TX_P2PKH_OUT_SIZE=34
TX_P2SH_SEGWIT_IN_SIZE=91
TX_P2SH_OUT_SIZE=32
TX_P2WPKH_IN_SIZE=69
TX_P2WPKH_OUT_SIZE=31

MAINNET_ADDRESS_REGEX="\([13][a-km-zA-HJ-NP-Z1-9]\{25,39\}\|bc1[qpzry9x8gf2tvdw0s][ac-hi-np-z02-9]\{7,86\}\|BC1[QPZRY9X8GF2TVDW0S][AC-HI-NP-Z02-9]\{7,86\}\)"
TESTNET_ADDRESS_REGEX="\([mn2][a-km-zA-HJ-NP-Z1-9]\{25,39\}\|\(bcrt1\|tb1\)[qpzry9x8gf2tvdw0s][ac-hi-np-z02-9]\{7,86\}\|TB1[QPZRY9X8GF2TVDW0S][AC-HI-NP-Z02-9]\{7,86\}\)"

TRUE=0
FALSE=1

# Common useful functions

function command_exists()
{
    command -v "$1" > /dev/null
}

function echoerr()
{
    (>&2 echo "$@")
}

function btc_amount_format()
{
    awk '{ print sprintf("%.8f", $1); }'
}

function bc_float_calc()
{
    echo "scale=8; $1" | bc | btc_amount_format
}

function call_bitcoin_cli()
{
    $bitcoin_cli "$@" || kill $$
}

function try_bitcoin_cli()
{
    $bitcoin_cli "$@" 2> /dev/null
}

# This will abort script with error message if multiple wallets are loaded
# and no -rpcwallet parameter is specified.
function check_multiwallet()
{
    call_bitcoin_cli getwalletinfo > /dev/null
}

function calc_tx_vsize()
{
    p2pkh_in_count=$1
    p2sh_segwit_in_count=$2
    p2wpkh_in_count=$3
    p2pkh_out_count=$4
    p2sh_out_count=$5
    p2wpkh_out_count=$6

    if [ "$p2sh_segwit_in_count" == "0" ] && [ "$p2wpkh_in_count" == "0" ]; then
        tx_size=$TX_FIXED_SIZE
    else
        tx_size=$TX_SEGWIT_FIXED_SIZE
        tx_size=$(( tx_size + p2sh_segwit_in_count * TX_P2SH_SEGWIT_IN_SIZE ))
        tx_size=$(( tx_size + p2wpkh_in_count * TX_P2WPKH_IN_SIZE ))
    fi
    tx_size=$(( tx_size + p2pkh_in_count * TX_P2PKH_IN_SIZE ))
    tx_size=$(( tx_size + p2pkh_out_count * TX_P2PKH_OUT_SIZE ))
    tx_size=$(( tx_size + p2sh_out_count * TX_P2SH_OUT_SIZE ))
    tx_size=$(( tx_size + p2wpkh_out_count * TX_P2WPKH_OUT_SIZE ))
    echo $tx_size
}

function is_p2pkh_bitcoin_address()
{
    [[ ${1:0:1} =~ ^[1mn] ]]
}

function is_p2sh_bitcoin_address()
{
    [[ ${1:0:1} =~ ^[23] ]]
}

function is_p2sh_segwit_bitcoin_address()
{
    [[ ${1:0:1} =~ ^[23] ]]
}

function is_bech32_bitcoin_address()
{
    [[ ${1:0:4} =~ ^(bc|BC|tb|TB)1[qpzry9x8gf2tvdw0sQPZRYXGFTVDWS] ]] || [[ ${1:0:6} =~ ^(bcrt|BCRT)1[qpzry9x8gf2tvdw0sQPZRYXGFTVDWS] ]]
}

function is_bech32m_bitcoin_address()
{
    [[ ${1:0:4} =~ ^(bc|BC|tb|TB)1[pzry9x8gf2tvdw0sPZRYXGFTVDWS] ]] || [[ ${1:0:6} =~ ^(bcrt|BCRT)1[pzry9x8gf2tvdw0sPZRYXGFTVDWS] ]]
}

function get_bitcoin_address_type()
{
    if is_p2pkh_bitcoin_address "$1"; then
        echo "p2pkh"
    elif is_p2sh_bitcoin_address "$1"; then
        echo "p2sh"
    elif is_bech32m_bitcoin_address "$1"; then
        echo "bech32m"
    elif is_bech32_bitcoin_address "$1"; then
        echo "bech32"
    fi
}

function getnewaddress_p2pkh()
{
    address=$(try_bitcoin_cli getnewaddress "" "legacy")
    if [ "$address" == "" ]; then
        address=$(call_bitcoin_cli getnewaddress)
    fi
    if ! is_p2pkh_bitcoin_address "$address"; then
        echoerr "FATAL: don't know how to generate P2PKH address!"
        kill $$
    fi
    echo "$address"
}

function getnewaddress_p2sh_segwit()
{
    address=$(try_bitcoin_cli getnewaddress "" "p2sh-segwit")
    if [ "$address" == "" ]; then
        address=$(call_bitcoin_cli getnewaddress)
        if is_p2pkh_bitcoin_address "$address"; then
            address=$(try_bitcoin_cli addwitnessaddress "$address")
        fi
    fi
    if ! is_p2sh_bitcoin_address "$address"; then
        echoerr "FATAL: don't know how to generate P2SH segwit address!"
        kill $$
    fi
    echo "$address"
}

function getnewaddress_bech32()
{
    address=$(try_bitcoin_cli getnewaddress "" "bech32")
    if ! is_bech32_bitcoin_address "$address"; then
        echoerr "FATAL: don't know how to generate bech32 address!"
        kill $$
    fi
    echo "$address"
}

# BTC amounts - is "$1" greater than or equal to "$2"
# Both BTC and satoshi amounts will actually work here
function is_btc_gte()
{
    (( \
        $(echo "$1" | btc_amount_format | tr -d '.' | sed 's/^0*//' | sed 's/^$/0/') \
            >= \
        $(echo "$2" | btc_amount_format | tr -d '.' | sed 's/^0*//' | sed 's/^$/0/') \
    ))
}
# is "$1" less than "$2"
function is_btc_lt()
{
    (( \
        $(echo "$1" | btc_amount_format | tr -d '.' | sed 's/^0*//' | sed 's/^$/0/') \
            < \
        $(echo "$2" | btc_amount_format | tr -d '.' | sed 's/^0*//' | sed 's/^$/0/') \
    ))
}
# is "$1" less than or equal to "$2"
function is_btc_lte()
{
    (( \
        $(echo "$1" | btc_amount_format | tr -d '.' | sed 's/^0*//' | sed 's/^$/0/') \
            <= \
        $(echo "$2" | btc_amount_format | tr -d '.' | sed 's/^0*//' | sed 's/^$/0/') \
    ))
}

function is_valid_bitcoin_address()
{
    if [ "$testnet" == "1" ]; then
        LANG=POSIX grep -qse "^${TESTNET_ADDRESS_REGEX}\$" <<< "$1"
        return $?
    else
        LANG=POSIX grep -qse "^${MAINNET_ADDRESS_REGEX}\$" <<< "$1"
        return $?
    fi
}

function is_valid_bitcoin_outpoint()
{
    grep -qsE "^[a-z0-9]{64}:[0-9]+$" <<< "$1"
}

function jq_btc_float()
{
    jq "$1" | btc_amount_format
}

function signrawtransactionwithkey()
{
    signedtx=$(try_bitcoin_cli signrawtransactionwithkey "$1" "$2" "$3" | jq -r ".hex")
    if [ "$signedtx" == "" ]; then
        signedtx=$(try_bitcoin_cli signrawtransaction "$1" "$3" "$2" | jq -r ".hex")
    fi
    if [ "$signedtx" == "" ]; then
        echoerr "FATAL: signing transaction with privkey failed."
        kill $$
    fi
    echo "$signedtx"
}

function signrawtransactionwithwallet()
{
    signedtx=$(try_bitcoin_cli signrawtransactionwithwallet "$1" | jq -r ".hex")
    if [ "$signedtx" == "" ]; then
        signedtx=$(try_bitcoin_cli signrawtransaction "$1" | jq -r ".hex")
    fi
    if [ "$signedtx" == "" ]; then
        echoerr "FATAL: signing transaction with wallet failed. Is wallet locked?"
        kill $$
    fi
    echo "$signedtx"
}

function sha256()
{
    if [[ "$(uname)" == "Darwin" ]]; then
        shasum -a 256
    else
        sha256sum
    fi
}

# Returns SHA-256d of input, where SHA-256d(x) = SHA-256(SHA-256(x))
function sha256d()
{
    echo -en "$(sha256 | grep -Eo "[a-z0-9]{64}" | sed 's/.\{2\}/\\x&/g')" | sha256 | grep -Eo "[a-z0-9]{64}"
}

# show_tx_by_id txid [blockhash]
function show_tx_by_id()
{
    rawtx="$(try_bitcoin_cli getrawtransaction "$1")"
    if [ "$rawtx" == "" ]; then
        rawtx="$(try_bitcoin_cli gettransaction "$1" true | jq -r ".hex")"
    fi
    if [ "$rawtx" == "" ] && [ "$2" != "" ]; then
        rawtx="$(try_bitcoin_cli getrawtransaction "$1" false "$2")"
    fi
    if [ "$rawtx" == "" ]; then
        echoerr "Failed to get transaction $1."
        echoerr "Use -txindex with Bitcoin Core to enable non-wallet and non-mempool blockchain transaction support."
        kill $$
    else
        echo "$rawtx" | call_bitcoin_cli -stdin decoderawtransaction
    fi
}

function has_index()
{
    indexinfo="$(call_bitcoin_cli "getindexinfo")"
    [[ "$indexinfo" != "null" ]]
}

# is_op_return_protocol_tx protocol_tag decodedtx
function is_op_return_protocol_tx()
{
    protocol_tag="$1"
    decodedtx="$2"
    readarray -t protocol_scripts < \
        <( echo "$2" | jq -r ".vout[].scriptPubKey.asm" | \
            grep "^OP_RETURN $protocol_tag")
    if (( ${#protocol_scripts[@]} > 0 )); then
        return $TRUE
    else
        return $FALSE
    fi
}

# is_omni_tx decodedtx
function is_omni_tx()
{
    is_op_return_protocol_tx "6f6d6e69" "$1"
}

# is_openassets_tx decodedtx
function is_openassets_tx()
{
    is_op_return_protocol_tx "4f41" "$1"
}

# is_likely_cj_tx decodedtx
function is_likely_cj_tx()
{
    decodedtx="$1"

    # Coinbase transactions can't be coinjoins.
    # Also, no known coinjoin implementations produce OP_RETURN outputs.
    # So we can quit early and skip any more parsing for them.
    if grep -qs "coinbase|OP_RETURN" <<< "$decodedtx"; then
        return $FALSE
    fi

    # Possible CJ tx rules:
    #   1) input count is 2 or more
    #   2) no address reuse in output side
    #   3) multiple equal value outputs to 2 or more different addresses
    #   4) number of inputs >= number of equal value outputs
    #   4) number of value outputs between number of outputs matching (1) to that * 2

    input_count="$(jq ".vin | length" <<< "$decodedtx")"
    if (( input_count < 2 )); then
        return $FALSE
    fi

    output_addresses_raw="$(get_decoded_tx_addresses "$decodedtx")"
    if [[ "$output_addresses_raw" != "$(uniq <<< "$output_addresses_raw")" ]]; then
        return $FALSE
    fi

    readarray -t output_values < <( echo "$1" | jq ".vout[].value" | \
        grep -v "^0$" )
    readarray -t equal_output_values < <( echo "${output_values[@]}" | \
        tr ' ' '\n' | sort | uniq -D | uniq )
    if (( ${#equal_output_values[@]} == 0 )); then
        return $FALSE
    fi

    readarray -t output_addresses <<< "$output_addresses_raw"
    equal_output_count=0
    equal_output_addresses=()
    for i in $(seq 0 $(( ${#output_values[@]} - 1 )) ); do
        if [[ " ${equal_output_values[@]} " =~ " ${output_values[$i]} " ]]; then
            ((equal_output_count++))
            equal_output_addresses+=("${output_addresses[$i]}")
        fi
    done
    unique_equal_output_addresses=($(echo "${equal_output_addresses[@]}" | \
        tr ' ' '\n' | sort -u | tr '\n' ' '))
    if \
        (( ${#unique_equal_output_addresses[@]} > 1 )) && \
        (( input_count >= equal_output_count )) && \
        (( ${#output_values[@]} >= equal_output_count )) && \
        (( ${#output_values[@]} <= $(( equal_output_count * 2 )) )) && \
        (( ${#unique_equal_output_addresses[@]} > 1 ))
    then
        return $TRUE
    else
        return $FALSE
    fi
}

function hr()
{
    if command_exists tput; then
        COLS=$(tput cols)
    else
        COLS=78
    fi
    printf "%0*d\n" $COLS | tr 0 "${1:--}"
}

# For compatibility between different Core versions (pre and 22.0+)
function get_decoded_tx_addresses()
{
    decodedtx="$1"
    addr0="$(echo "$decodedtx" | \
        jq -r ".vout[].scriptPubKey.addresses[0]" | head -n 1)"
    if [ "$addr0" == "null" ]; then
        echo "$decodedtx" | jq -r ".vout[].scriptPubKey.address"
    else
        echo "$decodedtx" | jq -r ".vout[].scriptPubKey.addresses[0]"
    fi
}

function show_decoded_tx_for_human()
{
    decodedtx="$1"
    txid="$(echo "$1" | jq -r ".txid")"
    wallettxdata="$(try_bitcoin_cli gettransaction "$txid" true)"
    if is_likely_cj_tx "$decodedtx"; then
        is_likely_cj="1"
    else
        is_likely_cj="0"
    fi
    echo "TxID: $txid"
    hr
    tx_vsize="$(echo "$1" | jq -r ".vsize")"
    tx_size="$(echo "$1" | jq -r ".size")"
    tx_weight="$(echo "$1" | jq -r ".weight")"
    echo "Size: $tx_vsize vB ($tx_size bytes, $tx_weight wu)"
    if [ "$wallettxdata" != "" ]; then
        confirmations="$(echo "$wallettxdata" | jq ".confirmations")"
        if [ "$confirmations" == "null" ] || [ "$confirmations" == "0" ]; then
            echo -n "Unconfirmed"
            if [ "$(echo "$wallettxdata" | jq -r ".[\"bip125-replaceable\"]")" == "yes" ]; then
                echo -n " (RBF)"
            fi
            echo ""
        else
            blockhash="$(echo "$wallettxdata" | jq -r ".blockhash")"
            blockheight="$(echo "$wallettxdata" | jq -r ".blockheight")"
            blocktime="$(echo "$wallettxdata" | jq -r ".blocktime")"
            echo "Included in block $blockhash (@$blockheight, $(date --iso-8601="seconds" -d @"$blocktime"))"
            echo "$confirmations confirmations"
        fi
    fi
    echo

    echo "Input(s):"
    readarray -t input_txids < <( echo "$1" | jq -r ".vin[].txid" )
    readarray -t input_vouts < <( echo "$1" | jq ".vin[].vout" )
    total_input_sum="0.00000000"
    if (( ${#input_txids[@]} == 0 )); then
        echo "(none)"
        has_total_input_sum="0"
    else
        has_total_input_sum="1"
        for i in $(seq 0 $(( ${#input_txids[@]} - 1 )) ); do
            echo -n "* "
            if   [ "${input_txids[$i]}" == "null" ] && \
                 [ "${input_vouts[$i]}" == "null" ]; then
                echo -n "(Coinbase)"
            else
                echo -n "${input_txids[$i]}:${input_vouts[$i]}"
            fi
            inputtx="$(try_bitcoin_cli getrawtransaction "${input_txids[$i]}")"
            if [ "$inputtx" == "" ]; then
                inputtx="$(try_bitcoin_cli gettransaction "${input_txids[$i]}")"
                if [ "$inputtx" != "" ]; then
                    inputtx="$(echo "$inputtx" | jq -r ".hex")"
                fi
            fi
            if [ "$inputtx" != "" ]; then
                inputtx="$(echo "$inputtx" | call_bitcoin_cli -stdin decoderawtransaction)"
            fi
            if [ "$inputtx" != "" ]; then
                inputaddress="$(echo "$inputtx" | jq -r ".vout[${input_vouts[$i]}].scriptPubKey.addresses[0]")"
                if [ "$inputaddress" == "null" ]; then
                    inputaddress="$(echo "$inputtx" | jq -r ".vout[${input_vouts[$i]}].scriptPubKey.address")"
                fi
                inputvalue="$(echo "$inputtx" | jq ".vout[${input_vouts[$i]}].value" | btc_amount_format)"
                if [ "$inputvalue" != "0.00000000" ]; then
                    echo -n " ($inputvalue BTC"
                    if [ "$inputaddress" != "none" ] && [ "$inputaddress" != "null" ]; then
                        echo -n " -> $inputaddress"
                        if  [ "$has_rpcwallet" == "1" ]; then
                            inputlabels="$(printf "$(call_bitcoin_cli getaddressinfo "$inputaddress" | jq -r ".labels[]")" | tr '\n' ',')"
                            if [ "$inputlabels" != "" ]; then
                                echo -n " [$inputlabels]"
                            fi
                        fi
                    fi
                    echo -n ")"
                    total_input_sum="$(bc_float_calc "$total_input_sum + $inputvalue")"
                fi
            else
                has_total_input_sum="0"
            fi
            echo
        done
    fi

    echo "Output(s):"
    total_output_sum="0.00000000"
    current_outnum="0"
    readarray -t output_addresses <<< "$(get_decoded_tx_addresses "$1")"
    readarray -t output_asms < <( echo "$1" | jq -r ".vout[].scriptPubKey.asm" )
    readarray -t output_values < <( echo "$1" | jq ".vout[].value" )
    if [ "$is_likely_cj" == "1" ]; then
        readarray -t equal_output_values < <( echo "${output_values[@]}" | tr ' ' '\n' | sort | uniq -D | uniq )
    fi
    if (( ${#input_txids[@]} == 0 )); then
        echo "(none)"
    else
        num_empty_outputs="0"
        for i in $(seq 0 $(( ${#output_addresses[@]} - 1 )) ); do
            # Don't output individual empty outputs, see https://mempool.emzy.de/testnet/tx/2d0a64a14faa9dc707dc84647a4e0dd1d4f31753e8a85574128bc8110e312e10
            if [ "${output_asms[$i]}" != "" ]; then
                echo -n "* $current_outnum: "
                amount="$(echo "${output_values[$i]}" | btc_amount_format)"
                if [ "$amount" != "0.00000000" ]; then
                    echo -n "$amount BTC -> "
                    total_output_sum="$(bc_float_calc "$total_output_sum + $amount")"
                fi
                output_address="${output_addresses[$i]}"
                if [ "$output_address" != "null" ]; then
                    echo -n "$output_address"
                    if [ "$is_likely_cj" == "1" ] && [ "$amount" != "0.00000000" ]; then
                        if [[ " ${equal_output_values[@]} " =~ " ${output_values[$i]} " ]]; then
                            echo -n " [cjout?]"
                        fi
                    fi
                    if [ "$has_rpcwallet" == "1" ]; then
                        outputlabels="$(printf "$(call_bitcoin_cli getaddressinfo "$output_address" | \
                            jq -r ".labels[]")" | tr '\n' ',')"
                        if [ "$outputlabels" != "" ]; then
                            echo -n " [$outputlabels]"
                        fi
                    fi
                else
                    echo -n "${output_asms[$i]}"
                    # Try decode human readable OP_RETURN's
                    if [[ ${output_asms[$i]} == OP_RETURN* ]]; then
                        output_asm="${output_asms[$i]}"
                        data="$(xxd -r -p  <<< "${output_asm:10}" | tr -d '\0')"
                        data_human="$(tr -cd "[:print:]\n" <<< "$data")"
                        if [ "$data" == "$data_human" ]; then
                            echo -en "\n  ($data)"
                        fi
                    fi
                fi
                echo
            else
                ((num_empty_outputs++))
            fi
            ((current_outnum++))
        done
        if [ "$num_empty_outputs" != "0" ]; then
            echo "* $num_empty_outputs empty outputs"
        fi
        if [ "$has_total_input_sum" == "1" ]; then
            echo -en "\nTotal input sum: $total_input_sum BTC"
        fi
        echo -e "\nTotal output sum: $total_output_sum BTC"
        if [ "$has_total_input_sum" == "1" ]; then
            fee="$(bc_float_calc "$total_input_sum - $total_output_sum")"
            feerate="$(echo "$fee * 100000000 / $tx_vsize" | bc)"
            echo "Fee: $(bc_float_calc "$total_input_sum - $total_output_sum") BTC ($feerate sat/vB)"
        fi
    fi
    hr
}

function get_tx_confirmations()
{
    confirmations=$(try_bitcoin_cli gettransaction "$1" true | jq ".confirmations")
    if [ "$confirmations" == "" ]; then
        confirmations=0
    fi
    echo $confirmations
}

function wait_for_tx_confirmations()
{
    txid=$1
    want_confirmations=$2
    if [ "$3" != "" ]; then
        check_frequency=$3
    else
        check_frequency=5
    fi
    while (( $(get_tx_confirmations "$txid") < want_confirmations )); do
        sleep $check_frequency
    done
}

function wait_for_block()
{
    want_blockheight=$1
    if [ "$2" != "" ]; then
        check_frequency=$2
    else
        check_frequency=5
    fi
    while (( $(call_bitcoin_cli getblockcount) < want_blockheight )); do
        sleep $check_frequency
    done
}

# Return txid for a signed hex-encoded transaction
# Result should be the same as sendrawtransaction return value, but without broadcasting transaction to the network.
# Will currently not work with SegWit transactions! (hence legacy prefix)
function legacy_tx_hexstring_to_txid()
{
    # sed magic from https://unix.stackexchange.com/questions/321860/reverse-a-hexadecimal-number-in-bash
    echo -en "$(sed 's/.\{2\}/\\x&/g')" | sha256d | sed -e 'G;:1' -e 's/\(..\)\(.*\n\)/\2\1/;t1' -e 's/.//'
}

# https://stackoverflow.com/a/42636717
function urldecode()
{
    while read -r; do
        echo -e "${REPLY//%/\\x}"
    done
}

function is_bip21_uri()
{
    if [ "$testnet" == "1" ]; then
        ADDRESS_REGEX="$TESTNET_ADDRESS_REGEX"
    else
        ADDRESS_REGEX="$MAINNET_ADDRESS_REGEX"
    fi
    if LANG=POSIX grep -qs "^[Bb][Ii][Tt][Cc][Oo][Ii][Nn]:${ADDRESS_REGEX}" <<< "$1"; then
        echo "1"
    fi
}

function bip21_get_address()
{
    if [ "$(is_bip21_uri "$1")" ]; then
        if [ "$testnet" == "1" ]; then
            LANG=POSIX grep -o "$TESTNET_ADDRESS_REGEX" <<< "$1"
        else
            LANG=POSIX grep -o "$MAINNET_ADDRESS_REGEX" <<< "$1"
        fi
    fi
}

function bip21_get_param()
{
    key="$2"
    if [ "$(is_bip21_uri "$1")" ]; then
        if grep -qs "${key}=" <<< "$1"; then
            echo "$1" | sed "s/.*${key}=//" | sed "s/&.*//" | urldecode
        fi
    fi
}

function randamount()
{
    minamount="$1"
    maxamount="$2"
    diff="$(bc_float_calc "$maxamount - $minamount")"
    bc_float_calc "$minamount + $RANDOM * $diff * 0.00003055581"
}

function is_http_url()
{
    input="$1"
    grep -qsE "^https?://" <<< "$input"
}

function is_hex_string()
{
    input="$1"
    grep -qsE "^[A-Za-z0-9]+$" <<< "$input"
}

function is_hex_id()
{
    input="$1"
    hexlen="$2"
    grep -qsE "^[A-Za-z0-9]{$hexlen}$" <<< "$input"
}

function get_hex_id_from_string()
{
    input="$1"
    hexlen="$2"
    grep -Eo "[A-Za-z0-9]{$hexlen}" <<< "$input"
}

function get_txid_from_outpoint()
{
    get_hex_id_from_string "$1" "64"
}

function get_vout_from_outpoint()
{
    grep -Eo ":[0-9]+$" <<< "$1" | tr -d ":"
}
