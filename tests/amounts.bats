#!/usr/bin/env bats

. ../inc.common.sh

@test "BTC amount format" {
    [[ "$(echo "1" | btc_amount_format)" == "1.00000000" ]]
    [[ "$(echo "21000000" | btc_amount_format)" == "21000000.00000000" ]]
    [[ "$(echo "0.01" | btc_amount_format)" == "0.01000000" ]]
    [[ "$(echo "0.000000012345" | btc_amount_format)" == "0.00000001" ]]
}

@test "BTC float calculations" {
    [[ "$(bc_float_calc "1 + 1")" == "2.00000000" ]]
    [[ "$(bc_float_calc "1 - 0.002")" == "0.99800000" ]]
    [[ "$(bc_float_calc "0.0001 * 2000")" == "0.20000000" ]]
    [[ "$(bc_float_calc "0.0001 * 0.01")" == "0.00000100" ]]
}

@test "BTC amount comparision" {
    is_btc_gte 2 1
    is_btc_gte 1 1
    is_btc_gte 2.1 1
    ! is_btc_gte 1 2

    is_btc_lt 1 2
    is_btc_lt 1.1 2.1
    ! is_btc_lt 2 1
    ! is_btc_lt 1 1

    is_btc_lte 1 2
    is_btc_lte 1.1 2.1
    is_btc_lte 1 1
    ! is_btc_lte 2 1
}
