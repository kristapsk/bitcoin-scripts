#! /bin/bash

. $(dirname $0)/inc.common.sh

if [ "$1" == "" ]; then
    echo "Usage: $(basename $0) [options] blocks"
    exit 0
fi

call_bitcoin_cli estimatesmartfee $1 | jq_btc_float ".feerate"

