#! /bin/bash

. $(dirname $0)/inc.common.sh

if [ "$1" == "" ]; then
    echo "Usage: $(basename $0) [options] blocks"
    exit 0
fi

feerate="$(call_bitcoin_cli estimatesmartfee $1 | jq_btc_float ".feerate")"
if [ "$feerate" == "0.00000000" ]; then
    feerate="$(call_bitcoin_cli getmempoolinfo | jq_btc_float ".mempoolminfee")"
fi
echo $feerate

