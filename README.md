# bitcoin-scripts

Various shell scripts, mainly to be used together with [Bitcoin Core](https://github.com/bitcoin/bitcoin) (bitcoind or bitcoin-qt) wallet.

Dependencies: `bash`, `bitcoin-cli` (v0.15 or newer), `awk`, `bc`, [`jq`](https://github.com/stedolan/jq), `sed`.

Scripts use Bitcoin JSON-RPC API, so it must be enabled in `bitcoin.conf` (`server=1`, `rpcuser=` and `rpcpassword=` settings).

Running each script without arguments will display usage. Most of the scripts will pass any options starting with dashes at the beginning of argument list directly to `bitcoin-cli` (like `-testnet` or `-rpcuser`).

None of scripts do wallet unlocking by itself, so you must call `bitcoin-cli walletpassphrase` before and `bitcoin-cli walletlock` afterwards manually when using scripts that sends out transactions (`fake-coinjoin.sh`, `ricochet-send.sh`), if your wallet is locked (it should be on mainnet).

| Script | Description |
| --- | --- |
| `estimatesmartfee.sh` | Calls `bitcoin-cli estimatesmartfee`. |
| `fake-coinjoin.sh` | Creates transaction that looks like a [CoinJoin](https://en.wikipedia.org/wiki/CoinJoin) transaction but all the inputs come and change outputs actually go to your own wallet. Could be useful if you want to send identical amount of funds to more than one recipient. |
| `randbtc.sh` | Outputs random BTC amount in between two amounts provided as arguments. |
| `ricochet-send.sh` | Implements [Ricochet Send](https://samouraiwallet.com/features/ricochet), which adds extra hops between the input(s) from your wallet and destination. |
| `timetoblocks.sh` | Converts human readable time interval string to expected number of Bitcoin blocks. |

## Examples

Send random amount between 0.001 and 0.002 BTC [donations](https://github.com/kristapsk/bitcoin-donation-addresses) using fake coinjoin. Will require enough P2PKH inputs with 5 or more confirmations in a wallet. Transaction will have two or more inputs from your wallet and two additional change outputs going back to your wallet (in addition to recipients).
```
$ ./fake-coinjoin.sh $(./randbtc.sh 0.001 0.002) 1andreas3batLhQa2FawWjeyjCqyBzypd 121kQfPpBGQ9KWPxvmTsgHEMe28Fj4ZffF
```

Send 0.001 BTC donation using ricochet send with 5 hops and 24 hour confirmation target.
```
$ ./ricochet-send.sh 0.001 1andreas3batLhQa2FawWjeyjCqyBzypd 5 $(./estimatesmartfee.sh $(./timetoblocks.sh "24 hours"))
```
