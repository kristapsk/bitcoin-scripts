#!/usr/bin/env bats

. ../inc.common.sh

@test "Outpoint validation" {
    is_valid_bitcoin_outpoint "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b:0"
}

@test "Outpoint splitting into txid and vout" {
    [[ $(get_txid_from_outpoint "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b:0") == "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b" ]]
    [[ $(get_vout_from_outpoint "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b:0") == "0" ]]
}
