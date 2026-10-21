# shellcheck shell=bash

${bitcoin_cli:?} stop
# Wait before deleting the datadir, including on failure.
while $bitcoin_cli getblockchaininfo &> /dev/null; do sleep 0.1; done
if [ "${retval:?}" == "0" ]; then
    sleep 1
    echo "OK, test passed successfully."
else
    echo "Test FAILED!"
fi
rm -rf "${bitcoin_test_datadir:?}"
exit "$retval"
