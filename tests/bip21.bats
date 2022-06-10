#!/usr/bin/env bats

. ../inc.common.sh

@test "BIP21 URI Scheme tests" {
    [[ "$(is_bip21_uri "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W")" ]]
    [[ "$(bip21_get_address "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W")" == "175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W" ]]

    [[ "$(is_bip21_uri "BITCOIN:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W")" ]]
    [[ "$(bip21_get_address "BITCOIN:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W")" == "175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W" ]]

    [[ "$(is_bip21_uri "BitCoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W")" ]]
    [[ "$(bip21_get_address "BitCoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W")" == "175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W" ]]

    [[ "$(is_bip21_uri "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?label=Luke-Jr")" ]]
    [[ "$(bip21_get_address "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?label=Luke-Jr")" == "175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W" ]]
    [[ "$(bip21_get_param "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?label=Luke-Jr" "label")" == "Luke-Jr" ]]

    [[ "$(is_bip21_uri "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?amount=20.3&label=Luke-Jr")" ]]
    [[ "$(bip21_get_address "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?amount=20.3&label=Luke-Jr")" == "175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W" ]]
    [[ "$(bip21_get_param "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?amount=20.3&label=Luke-Jr" "label")" == "Luke-Jr" ]]
    [[ "$(bip21_get_param "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?amount=20.3&label=Luke-Jr" "amount")" == "20.3" ]]

    [[ "$(is_bip21_uri "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?amount=50&label=Luke-Jr&message=Donation%20for%20project%20xyz")" ]]
    [[ "$(bip21_get_address "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?amount=50&label=Luke-Jr&message=Donation%20for%20project%20xyz")" == "175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W" ]]
    [[ "$(bip21_get_param "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?amount=50&label=Luke-Jr&message=Donation%20for%20project%20xyz" "label")" == "Luke-Jr" ]]
    [[ "$(bip21_get_param "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?amount=50&label=Luke-Jr&message=Donation%20for%20project%20xyz" "amount")" == "50" ]]
    [[ "$(bip21_get_param "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?amount=50&label=Luke-Jr&message=Donation%20for%20project%20xyz" "message")" == "Donation for project xyz" ]]

    [[ "$(is_bip21_uri "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?somethingyoudontunderstand=50&somethingelseyoudontget=999")" ]]
    [[ "$(bip21_get_address "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?somethingyoudontunderstand=50&somethingelseyoudontget=999")" == "175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W" ]]
    [[ "$(bip21_get_param "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?somethingyoudontunderstand=50&somethingelseyoudontget=999" "somethingyoudontunderstand")" == "50" ]]
    [[ "$(bip21_get_param "bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?somethingyoudontunderstand=50&somethingelseyoudontget=999" "somethingelseyoudontget")" == "999" ]]
}

@test "urldecode tests" {
    [[ "$(urldecode <<< "%7Bfoo%7D")" == "{foo}" ]]
    [[ "$(urldecode <<< "Donation%20for%20project%20xyz")" == "Donation for project xyz" ]]
}
