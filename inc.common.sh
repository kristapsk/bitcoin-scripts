bitcoin_cli="bitcoin-cli"
bitcoin_cli_options=""
testnet=0

# assume all first parameters beginning with dash are bitcoin-cli options
while (( ${#} > 0 )) && [[ ${1:0:1} == "-" ]]; do
    bitcoin_cli_options="$bitcoin_cli_options $1"
    if [ "$1" == "-regtest" ] || [ "$1" == "-testnet" ]; then
        testnet=1
    fi
    shift
done
bitcoin_cli="$bitcoin_cli$bitcoin_cli_options"

# Some constants
# We assume no more than 253 TX inputs or outputs
TX_INPUTS_MAX=253
TX_OUTPUTS_MAX=253
TX_FIXED_SIZE=10
TX_SEGWIT_FIXED_SIZE=12
TX_P2PKH_IN_SIZE=148
TX_P2PKH_OUT_SIZE=34
TX_P2SH_SEGWIT_IN_SIZE=41
TX_P2SH_SEGWIT_WITNESS_SIZE=109
TX_P2SH_OUT_SIZE=34
TX_P2WPKH_IN_SIZE=18
TX_P2WPKH_WITNESS_SIZE=109
TX_P2WPKH_OUT_SIZE=33

# Common useful functions

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
        tx_size=$(( $tx_size + $p2pkh_in_count * $TX_P2PKH_IN_SIZE ))
        tx_size=$(( $tx_size + $p2pkh_out_count * $TX_P2PKH_OUT_SIZE ))
        tx_size=$(( $tx_size + $p2sh_out_count * $TX_P2SH_OUT_SIZE ))
        tx_size=$(( $tx_size +  $p2wpkh_out_count * $TX_P2WPKH_OUT_SIZE ))
        echo $tx_size
    else
        tx_vsize=$(( $TX_FIXED_SIZE * 3 + $TX_SEGWIT_FIXED_SIZE ))
        tx_vsize=$(( $tx_vsize + $p2pkh_in_count * $TX_P2PKH_IN_SIZE * 4 ))
        tx_vsize=$(( $tx_vsize + $p2sh_segwit_in_count * ($TX_P2SH_SEGWIT_IN_SIZE * 4 + $TX_P2SH_SEGWIT_WITNESS_SIZE * 3) ))
        tx_vsize=$(( $tx_vsize + $p2wpkh_in_count * ($TX_P2WPKH_IN_SIZE * 4 + $TX_P2WPKH_WITNESS_SIZE * 3) ))
        tx_vsize=$(( $tx_vsize + $p2pkh_out_count * $TX_P2PKH_OUT_SIZE * 4 ))
        tx_vsize=$(( $tx_vsize + $p2sh_out_count * $TX_P2SH_OUT_SIZE * 4 ))
        tx_vsize=$(( $tx_vsize + $p2wpkh_out_count * $TX_P2WPKH_OUT_SIZE * 4 ))
        tx_vsize=$(( ($tx_vsize + 1) / 4 ))
        echo $tx_vsize
    fi
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
    [[ ${1:0:3} =~ ^(bc|BC|tb|TB)1 ]]
}

function get_bitcoin_address_type()
{
    if is_p2pkh_bitcoin_address "$1"; then
        echo "p2pkh"
    elif is_p2sh_bitcoin_address "$1"; then
        echo "p2sh"
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
    if ! is_p2pkh_bitcoin_address $address; then
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
        if is_p2pkh_bitcoin_address $address; then
            address=$(try_bitcoin_cli addwitnessaddress $address)
        fi
    fi
    if ! is_p2sh_bitcoin_address $address; then
        echoerr "FATAL: don't know how to generate P2SH segwit address!"
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

function is_valid_bitcoin_address()
{
    if [ "$testnet" == "1" ]; then
        echo $1 | LANG=POSIX grep -qse '^\([mn2][a-km-zA-HJ-NP-Z1-9]\{25,39\}\|tb1[a-z0-9]\{8,87\}\|TB1[A-Z0-9]\{8,87\}\)$'
        return $?
    else
        echo $1 | LANG=POSIX grep -qse  '^\([13][a-km-zA-HJ-NP-Z1-9]\{25,39\}\|bc1[a-z0-9]\{8,87\}\|BC1[A-Z0-9]\{8,87\}\)$'
        return $?
    fi
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

# Returns SHA-256d of input, where SHA-256d(x) = SHA-256(SHA-256(x))
function sha256d()
{
    echo -en "$(sha256sum | grep -Eo "[a-z0-9]{64}" | sed 's/.\{2\}/\\x&/g')" | sha256sum | grep -Eo "[a-z0-9]{64}"
}

function show_tx_by_id()
{
    call_bitcoin_cli getrawtransaction "$1" | call_bitcoin_cli -stdin decoderawtransaction
}

function get_tx_confirmations()
{
    confirmations=$(try_bitcoin_cli gettransaction "$1" | jq ".confirmations")
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
    while (( $(get_tx_confirmations $txid) < $want_confirmations )); do
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

