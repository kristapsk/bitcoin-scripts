# shellcheck shell=bash

if [ "${retval:?}" == "0" ]; then
    ${bitcoin_cli:?} stop
    # Wait until bitcoind has stopped properly
    while $bitcoin_cli getblockchaininfo &> /dev/null; do sleep 0.1; done
    sleep 1
    echo "OK, test passed successfully."
else
    echo "Test FAILED!"
fi
exit "$retval"
