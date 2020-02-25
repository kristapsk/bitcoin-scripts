#!/usr/bin/env bash
set -x
"$(dirname "$0")/test_fake-coinjoin.sh" || exit 1
"$(dirname "$0")/test_ricochet-send.sh" || exit 1
"$(dirname "$0")/test_ricochet-send-from.sh" || exit 1
echo "All tests PASSED!"
