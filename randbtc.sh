#! /bin/bash

. $(dirname $0)/inc.common.sh

if [ "$2" == "" ]; then
    echo "Usage: $(basename $0) minamount maxamount"
    exit
fi

minamount=$1
maxamount=$2

diff=$(bc_float_calc "$maxamount - $minamount")

bc_float_calc "$minamount + $RANDOM * $diff * 0.00003055581"

