# bitcoin-scripts

Various shell scripts, mainly to be used together with [Bitcoin Core](https://github.com/bitcoin/bitcoin) (bitcoind or bitcoin-qt) wallet.

Dependencies: `bash`, `bitcoin-cli` (v0.15 or newer), `awk`, `bc`, [`jq`](https://github.com/stedolan/jq), `sed`.

Scripts use Bitcoin JSON-RPC API, so it must be enabled in `bitcoin.conf` (`server=1`, `rpcuser=` and `rpcpassword=` settings).

Running each script without arguments will display usage. Most of the scripts will pass any options starting with dashes at the beginning of argument list directly to `bitcoin-cli` (like `-testnet` or `-rpcuser`).

None of scripts do wallet unlocking by itself, so you must call `bitcoin-cli walletpassphrase` before and `bitcoin-cli walletlock` afterwards manually when using scripts that sends out transactions (`fake-coinjoin.sh`, `ricochet-send.sh`), if your wallet is locked (it should be on mainnet).

| Script | Description |
| --- | --- |
| `blockheightat.sh` | Returns last block height before specified date/time. |
| `checktransaction.sh` | Displays basic information about Bitcoin transaction(s) in human readable form. |
| `estimatesmartfee.sh` | Calls `bitcoin-cli estimatesmartfee`. |
| `fake-coinjoin.sh` | Creates transaction that looks like a [CoinJoin](https://bitcoin.org/en/developer-guide#coinjoin) transaction but all the inputs come and change outputs actually go to your own wallet. Could be useful if you want to send identical amount of funds to more than one recipient. |
| `listpossiblecjtxids.sh` | Lists txid's of transactions in given block that could potentially be CoinJoin transactions. Note that it does not analyze input amounts (as it's hard to do without -txindex), so will likely give a lot of false positives. |
| `randbtc.sh` | Outputs random BTC amount in between two amounts provided as arguments. [Round number amounts](https://en.bitcoin.it/Privacy#Round_numbers) can decrease your privacy. |
| `ricochet-send.sh` | Implements [Ricochet Send](https://samouraiwallet.com/ricochet), which adds extra hops between the input(s) from your wallet and destination. |
| `ricochet-send-from.sh` | Alternative implementation of Ricochet Send where instead of specifying amount to send you specify source address and all coins from that address is sent. |
| `timetoblocks.sh` | Converts human readable time interval string to expected number of Bitcoin blocks. |

## Examples

Send random amount between 0.001 and 0.002 BTC [donations](https://github.com/kristapsk/bitcoin-donation-addresses) using fake coinjoin. Will require enough P2PKH inputs with 5 or more confirmations in a wallet. Transaction will have two or more inputs from your wallet and two additional change outputs going back to your wallet (in addition to recipients).
```
$ ./fake-coinjoin.sh $(./randbtc.sh 0.001 0.002) 1andreas3batLhQa2FawWjeyjCqyBzypd 3N6qaU3bnF43u4YTFKQf8usd3UqvyShovS
```

Send 0.001 BTC donation using ricochet send with 5 hops and 24 hour confirmation target.
```
$ ./ricochet-send.sh 0.001 1andreas3batLhQa2FawWjeyjCqyBzypd 5 $(./estimatesmartfee.sh $(./timetoblocks.sh "24 hours"))
```
## Support

[![tippin.me](https://badgen.net/badge/%E2%9A%A1%EF%B8%8Ftippin.me/@kristapsk/F0918E)](https://tippin.me/@kristapsk)

If you find these scripts useful, you can support development by sending some Bitcoin to 3BGEw1eLeu1xrcRVogvHbqNqWWLtmB2BTM. Or use tippin.me link above for tips via Lightning Network.
