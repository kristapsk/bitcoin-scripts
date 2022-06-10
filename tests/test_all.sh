#!/usr/bin/env bash
cd "$(dirname "$0")" > /dev/null || exit
for f in *.bats; do
    echo "Running $f"
    "./$f"
    echo ""
done
