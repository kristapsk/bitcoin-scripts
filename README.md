# bitcoin-scripts

Various shell scripts, mainly to be used together with [Bitcoin Core](https://github.com/bitcoin/bitcoin) (bitcoind or bitcoin-qt) wallet. I also have [some scripts for CLN (Core Lightning / c-lightning)](https://github.com/kristapsk/cln-scripts).

## Installation

Dependencies: `bash` 4+, `bitcoin-cli` (v0.17 or newer), `awk`, `bc`, [`jq`](https://github.com/stedolan/jq), `sed`.

Gentoo Linux users can use [my portage overlay](https://github.com/kristapsk/portage-overlay):
```sh
# eselect repository add kristapsk git https://github.com/kristapsk/portage-overlay.git
# emerge -av bitcoin-scripts
```

Otherwise, use provided `install.sh` script, which will install everything in `/opt/bitcoin-scripts` with symlinks in `/usr/local/bin` (so that they are on `PATH`).

## Usage

Scripts use Bitcoin JSON-RPC API, so it must be enabled in `bitcoin.conf` (`server=1`, `rpcuser=` and `rpcpassword=` settings).

Running each script without arguments will display usage. Most of the scripts will pass any options starting with dashes at the beginning of argument list directly to `bitcoin-cli` (like `-testnet` or `-rpcuser`).

None of scripts do wallet unlocking by itself, so you must call `bitcoin-cli walletpassphrase` before and `bitcoin-cli walletlock` afterwards manually when using scripts that sends out transactions (`fake-coinjoin.sh`, `ricochet-send.sh`), if your wallet is locked (it should be on mainnet).

When installed system wide, call them with `bc-` prefix, without `.sh` suffix (so `checktransaction.sh` becomes `bc-checktransaction`).

| Script | Description |
| --- | --- |
| `blockheightat.sh` | Returns last block height before specified date/time. |
| `checktransaction.sh` | Displays basic information about Bitcoin transaction(s) in human readable form. |
| `estimatesmartfee.sh` | Calls `bitcoin-cli estimatesmartfee`. |
| `fake-coinjoin.sh` | Creates transaction that looks like a [CoinJoin](https://en.bitcoin.it/wiki/CoinJoin) transaction but all the inputs come and change outputs actually go to your own wallet. Could be useful if you want to send identical amount of funds to more than one recipient. |
| `listpossiblecjtxids.sh` | Lists txid's of transactions in given block that could potentially be CoinJoin transactions. Note that it does not analyze input amounts (as it's hard to do without -txindex), so will likely give a lot of false positives. |
| `randbtc.sh` | Outputs random BTC amount in between two amounts provided as arguments. [Round number amounts](https://en.bitcoin.it/Privacy#Round_numbers) can decrease your privacy. |
| `ricochet-send.sh` | Implements [Ricochet Send](https://samouraiwallet.com/ricochet), which adds extra hops between the input(s) from your wallet and destination. |
| `ricochet-send-from.sh` | Alternative implementation of Ricochet Send where instead of specifying amount to send you specify source address and all coins from that address is sent. |
| `timetoblocks.sh` | Converts human readable time interval string to expected number of Bitcoin blocks. |
| `whitepaper.sh` | Retrieves PDF of original Bitcoin Whitepaper by Satoshi Nakamoto from the Bitcoin blockchain. |

## Examples

Send random amount between 0.001 and 0.002 BTC donation to me and [Sci-Hub](https://en.wikipedia.org/wiki/Sci-Hub) (here's [some list of Bitcoin donation addresses](https://github.com/kristapsk/bitcoin-donation-addresses)) using fake coinjoin. Will require enough confirmed inputs previously sent to native segwit p2wpkh bech32 addresses in a wallet. Transaction will have two or more inputs from your wallet and two additional change outputs going back to your wallet (in addition to recipients).
```
$ ./fake-coinjoin.sh $(./randbtc.sh 0.001 0.002) bc1q7eqheemcu6xpgr42vl0ayel6wj087nxdfjfndf bc1qwfafhs3ztp5d78n3jwwvlel0m7g0njj949zdya
```

Send 0.001 BTC donation using ricochet send with 5 hops and 24 hour confirmation target.
```
$ ./ricochet-send.sh 0.001 bc1qwfafhs3ztp5d78n3jwwvlel0m7g0njj949zdya 5 $(./estimatesmartfee.sh $(./timetoblocks.sh "24 hours"))
```
## Support

If you want to support my work on this project and other free software (I am also maintainer of [JoinMarket](https://github.com/JoinMarket-Org/joinmarket-clientserver) and do other Bitcoin stuff), you can send some sats (Bitcoin) [here](https://donate.kristapsk.lv/) (that's my self-hosted [SatSale](https://github.com/nickfarrow/SatSale) instance).

There is also static donation address used in examples above - `bc1qwfafhs3ztp5d78n3jwwvlel0m7g0njj949zdya` ([signed](donation-address.txt.asc) with [my signature](https://github.com/JoinMarket-Org/joinmarket-clientserver/blob/709db9ea3b7a18a070e8b76943d57bdfad46df60/pubkeys/KristapsKaupe.asc)).
