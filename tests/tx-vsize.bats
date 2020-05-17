#!/usr/bin/env bats

. ../inc.common.sh

@test "Transaction vsize calculation" {
    # 1 P2PKH input, 1 P2PKH output
    [[ "$(calc_tx_vsize 1 0 0 1 0 0)" == "192" ]]
    # 1 P2PKH input, 2 P2PKH outputs
    [[ "$(calc_tx_vsize 1 0 0 2 0 0)" == "226" ]]
    # 1 P2PKH input, 2 P2SH outputs
    [[ "$(calc_tx_vsize 1 0 0 0 2 0)" == "222" ]]
    # 1 P2PKH input, 1 P2PKH output, 1 P2SH output
    [[ "$(calc_tx_vsize 1 0 0 1 1 0)" == "224" ]]
    # 1 P2SH segwit input, 1 P2SH output
    [[ "$(calc_tx_vsize 0 1 0 0 1 0)" == "134" ]]
    # 1 P2WPKH input, 1 P2WPKH output
    [[ "$(calc_tx_vsize 0 0 1 0 0 1)" == "111" ]]
}

