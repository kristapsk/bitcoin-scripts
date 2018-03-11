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

# Common useful functions

function btc_amount_format()
{
    awk '{ print sprintf("%.8f", $1); }'
}

function bc_float_calc()
{
    echo "$1" | bc | btc_amount_format
}

function call_bitcoin_cli()
{
    $bitcoin_cli "$@" || kill $$
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

function is_p2pkh_bitcoin_address()
{
    [[ ${1:0:1} =~ ^[1mn] ]]
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

