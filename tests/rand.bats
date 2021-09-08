#!/usr/bin/env bats

. ../inc.common.sh

@test "Randomization" {
    is_btc_gte "$(randamount "0.1" "0.2")" "0.1"
    is_btc_lte "$(randamount "0.1" "0.2")" "0.2"
}
