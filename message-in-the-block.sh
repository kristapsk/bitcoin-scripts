#!/usr/bin/env bash

# shellcheck disable=SC1091
# shellcheck source=./inc.common.sh
. "$(dirname "$0")/inc.common.sh"

if [[ -z "$2" ]]; then
    echo "Usage: $(basename "$0") blockheight message [txfee [change_address]]"
    echo "Where:"
    echo "  blockheight     - try to write message at this blockheight (not guranteed to be exact, but will not be before)"
    echo "  message         - hex data for OP_RETURN output, up to 80 bytes (use \`echo -n \"message\" | od -t x1 -A n | tr -d \" \"\` to convert from ASCII)"
    echo "  txfee           - transaction fee per kvB (default: \"estimatesmartfee 1\", currently $($(dirname "$0")/estimatesmartfee.sh $bitcoin_cli_options 1) BTC)"
    echo "  change_address  - optional change address (default is to create new address in wallet)"
    exit 1
fi

function check_blockheight_future()
{
    current_blockheight="$(call_bitcoin_cli getblockcount)"
    if (( target_blockheight <= current_blockheight )); then
        echoerr "Target blockheight must be in future! (current blockheight: $current_blockheight)"
        kill $$
    fi
}

target_blockheight="$1"
if ! grep -qsE "^[0-9]+$" <<< "$1"; then
    echoerr "Target blockheight $target_blockheight is not a number!"
    exit 2
fi
check_blockheight_future
# nLockTime specifies the block number AFTER which this transaction can be included in a block.
((target_blockheight--))

message="$2"
if ! grep -qsE "[A-Za-z0-9]{2,160}" <<< "$message"; then
    echoerr "Message '$message' is not a valid hex data! (too long or not hex)"
    exit 2
fi

if [[ -n "$3" ]]; then
    txfee="$3"
else
    txfee="$($(dirname "$0")/estimatesmartfee.sh $bitcoin_cli_options 1)"
fi

if [[ -n "$4" ]]; then
    if is_valid_bitcoin_address "$4"; then
        change_addr="$4"
    else
        echoerr "$4 is not a valid Bitcoin address!"
        exit 2
    fi
else
    change_addr="$(call_bitcoin_cli getnewaddress)"
fi

rawtx=$(call_bitcoin_cli createrawtransaction "[]" "[{\"data\":\"$message\"}]" "$target_blockheight")
rawtx=$(call_bitcoin_cli fundrawtransaction "$rawtx" "{\"changeAddress\":\"$change_addr\",\"feeRate\":$txfee}" | jq -r ".hex")
call_bitcoin_cli decoderawtransaction "$rawtx"

read -p "Sign and broadcast this transaction? " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    signedtx=$(signrawtransactionwithwallet "$rawtx")
    echo "Waiting for blockchain tip @ $target_blockheight"
    wait_for_block "$target_blockheight"
    txid=$(call_bitcoin_cli sendrawtransaction "$signedtx")
    echo "Sent transaction $txid"
fi
