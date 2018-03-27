# bitcoin-scripts

Various shell scripts, mainly to be used together with [Bitcoin Core](https://github.com/bitcoin/bitcoin) (bitcoind or bitcoin-qt) wallet. Still needs some work and more testing, use on mainnet at your own risk (although possibility of loss of funds should not be big, as no transaction sending funds outside your wallet are broadcasted without confirmation).

Dependencies: `bash`, `bitcoin-cli`, `awk`, `bc`, [`jq`](https://github.com/stedolan/jq), `sed`.

Running each script without arguments will display usage. Most of the scripts will pass any options starting with dashes at the beginning of argument list directly to `bitcoin-cli`.

| Script | Description |
| --- | --- |
| `estimatesmartfee.sh` | Calls `bitcoin-cli estimatesmartfee`. |
| `fake-coinjoin.sh` | Creates transaction that looks like a [CoinJoin](https://en.wikipedia.org/wiki/CoinJoin) transaction but all the inputs come and change outputs actually go to your own wallet. Could be useful if you want to send identical amount of funds to more than one recipient. |
| `randbtc.sh` | Outputs random BTC amount in between two amounts provided as arguments. |
| `ricochet-send.sh` | Implements [Ricochet Send](https://samouraiwallet.com/features/ricochet), which adds extra hops between the input(s) from your wallet and destination. |
| `timetoblocks.sh` | Converts human readable time interval string to expected number of Bitcoin blocks. |
