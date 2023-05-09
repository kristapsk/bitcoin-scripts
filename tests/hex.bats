#!/usr/bin/env bats

. ../inc.common.sh

@test "Hex id matching tests" {
    $(is_hex_id "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f" "64")
    $(is_hex_id "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b" "64")
    ! $(is_hex_id "not a hex id" "12")
    ! $(is_hex_id "not a hex id" "64")
    ! $(is_hex_id "" "64")
    # wrong length
    ! $(is_hex_id "123456789" "2")
}

@test "Hex string matching tests" {
    $(is_hex_string "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f")
    $(is_hex_string "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b")
    $(is_hex_string "123456789")
    ! $(is_hex_string "not a hex string")
    ! $(is_hex_string "not a hex string")
    ! $(is_hex_string "")
}

@test "Hex substring matching tests" {
    [[ "$(get_hex_id_from_string "https://blockstream.info/tx/4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b" "64")" == "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b" ]]
}
