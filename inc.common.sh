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
TX_P2WSH_IN_SIZE=41
TX_P2WSH_WITNESS_SIZE=109
TX_P2SH_OUT_SIZE=34

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

function is_p2pkh_bitcoin_address()
{
    [[ ${1:0:1} =~ ^[1mn] ]]
}

function is_p2sh_bitcoin_address()
{
    [[ ${1:0:1} =~ ^[23] ]]
}

function is_p2wsh_bitcoin_address()
{
    #is_p2sh_bitcoin_address
    [[ ${1:0:1} =~ ^[23] ]]
}

function getnewaddress_p2pkh()
{
    address=$(call_bitcoin_cli getnewaddress)
    if ! is_p2pkh_bitcoin_address $address; then
        echoerr "FATAL: getnewaddress returns non-P2PKH address!"
        kill $$
    fi
    echo "$address"
}

function getnewaddress_p2wsh()
{
    address=$(call_bitcoin_cli getnewaddress)
    if is_p2pkh_bitcoin_address $address; then
        address=$(call_bitcoin_cli addwitnessaddress $address)
    fi
    if ! is_p2sh_bitcoin_address $address; then
        echoerr "FATAL: don't know how to generate P2WSH address!"
        kill $$
    fi
    echo "$address"
}

# BTC amounts - is "$1" greater than or equal to "#2"
# Both BTC and satoshi amounts will actually work here
function is_btc_gte()
{
    (( \
        $(echo "$1" | btc_amount_format | tr -d '.' | sed 's/^0*//' | sed 's/^$/0/') \
            >= \
        $(echo "$2" | btc_amount_format | tr -d '.' | sed 's/^0*//' | sed 's/^$/0/') \
    ))
}

# Only P2PKH/P2SH supported for now, no bech32.
function is_valid_bitcoin_address()
{
    if [ "$testnet" == "1" ]; then
        echo $1 | grep -qse '^[mn2][a-km-zA-HJ-NP-Z1-9]\{25,34\}$'
        return $?
    else
        echo $1 | grep -qse '^[13][a-km-zA-HJ-NP-Z1-9]\{25,34\}$'
        return $?
    fi
}

function jq_btc_float()
{
    jq "$1" | btc_amount_format
}

function show_tx_by_id()
{
    call_bitcoin_cli decoderawtransaction \
        $(call_bitcoin_cli getrawtransaction "$1")
}

