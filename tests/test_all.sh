#!/usr/bin/env bash
cd $(dirname "$0") > /dev/null
for f in *.bats; do
    echo "Running $f"
    ./$f
    echo ""
done
