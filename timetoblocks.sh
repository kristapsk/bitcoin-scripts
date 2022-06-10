#!/usr/bin/env bash

# Average block time in seconds
BLOCKTIME=600

if [ "$1" == "" ]; then
    echo "Usage: $(basename "$0") [interval]"
    exit 0
fi

echo $(( ( $(date +"%s") - $(date -d "$1 ago" +"%s") ) / BLOCKTIME ))
