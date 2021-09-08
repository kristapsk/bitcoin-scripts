#!/usr/bin/env bash

. $(dirname $0)/inc.common.sh

if [ "$2" == "" ]; then
    echo "Usage: $(basename $0) minamount maxamount"
    exit
fi

randamount "$1" "$2"
