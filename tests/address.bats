#!/usr/bin/env bats

. ../inc.common.sh

@test "P2PKH mainnet address validation" {
    testnet=0
    addresses=()
    addresses+=("1BvBMSEYstWetqTFn5Au4m4GFg7xJaNVN2")

    for i in $(seq 0 $(( ${#addresses[@]} - 1 )) ); do
        is_valid_bitcoin_address ${addresses[$i]}
        is_p2pkh_bitcoin_address ${addresses[$i]}
        [[ "$(get_bitcoin_address_type ${addresses[$i]})" == "p2pkh" ]]
    done
}

@test "P2PKH testnet address validation" {
    testnet=1
    addresses=()
    addresses+=("ms4VLdD9sFGMureHo378jziwKKjx3uKZLw")

    for i in $(seq 0 $(( ${#addresses[@]} - 1 )) ); do
        is_valid_bitcoin_address ${addresses[$i]}
        is_p2pkh_bitcoin_address ${addresses[$i]}
        [[ "$(get_bitcoin_address_type ${addresses[$i]})" == "p2pkh" ]]
    done
}

@test "P2SH mainnet address validation" {
    testnet=0
    addresses=()
    addresses+=("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy")
    addresses+=("3QJmV3qfvL9SuYo34YihAf3sRCW3qSinyC")

    for i in $(seq 0 $(( ${#addresses[@]} - 1 )) ); do
        is_valid_bitcoin_address ${addresses[$i]}
        is_p2sh_bitcoin_address ${addresses[$i]}
        [[ "$(get_bitcoin_address_type ${addresses[$i]})" == "p2sh" ]]
    done
}

@test "P2SH testnet address validation" {
    testnet=1
    addresses=()
    addresses+=("2N41z1ZYTZ6WVzcw7nDaJKh421bhM2v6Bak")

    for i in $(seq 0 $(( ${#addresses[@]} - 1 )) ); do
        is_valid_bitcoin_address ${addresses[$i]}
        is_p2sh_bitcoin_address ${addresses[$i]}
        [[ "$(get_bitcoin_address_type ${addresses[$i]})" == "p2sh" ]]
    done
}

