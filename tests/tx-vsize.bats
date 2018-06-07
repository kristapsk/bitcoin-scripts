#!/usr/bin/env bats

. ../inc.common.sh

@test "Transaction vsize calculation" {
    # 1 P2PKH input, 1 P2PKH output
    [[ "$(calc_tx_vsize 1 0 1 0)" == "192" ]]
    # 1 P2PKH input, 2 P2PKH outputs
    [[ "$(calc_tx_vsize 1 0 2 0)" == "226" ]]
    # 1 P2PKH input, 2 P2SH outputs
    [[ "$(calc_tx_vsize 1 0 0 2)" == "226" ]]
    # 1 P2PKH input, 1 P2PKH output, 1 P2SH output
    [[ "$(calc_tx_vsize 1 0 1 1)" == "226" ]]
    # 1 P2WSH input, 1 P2SH output
    [[ "$(calc_tx_vsize 0 1 0 1)" == "167" ]]
}

