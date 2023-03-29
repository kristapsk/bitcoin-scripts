#!/usr/bin/env bash

# shellcheck disable=SC1091
# shellcheck source=./inc.common.sh
. "$(dirname "$(readlink -m "$0")")/inc.common.sh"

if [ "$2" == "" ]; then
    echo "Usage: $(basename "$0") minamount maxamount"
    exit
fi

randamount "$(tr ',' '.' <<< "$1")" "$(tr ',' '.' <<< "$2")"
