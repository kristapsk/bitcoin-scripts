#!/usr/bin/env bash
# shellcheck disable=SC2016

if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "Installs Bitcoin scripts."
    echo "Usage: $(basename "$0")"
    exit
fi

PREFIX="/opt/bitcoin-scripts"

if [[ "$(whoami)" == "root" ]]; then
    sudo=""
else
    sudo="sudo"
fi

cd "$(dirname "$0")" || exit 1

$sudo mkdir -p "$PREFIX"

echo -n "Installing inc.common.sh..."
$sudo install -p -t "$PREFIX" -m 644 ./inc.common.sh
echo ""

DOC_LIST="
    donation-address.txt.asc
    README.md
"

for doc in $DOC_LIST; do
    echo -n "Installing $doc..."
    $sudo cp "$doc" "$PREFIX"
    echo ""
done

SCRIPT_LIST="
    blockheightat
    checktransaction
    estimatesmartfee
    fake-coinjoin
    listpossiblecjtxids
    randbtc
    ricochet-send-from
    ricochet-send
    timetoblocks
    whitepaper
"

for script in $SCRIPT_LIST; do
    echo -n "Installing bc-$script..."
    $sudo install -p -t "$PREFIX" "./$script.sh"
    $sudo ln -f -s "$PREFIX/$script.sh" "/usr/local/bin/bc-$script"
    echo ""
done

echo -n "Creating bc-scripts-uninstall..."
$sudo bash -c 'cat <<EOF > '"$PREFIX/bc-scripts-uninstall.sh"'
#!/usr/bin/env bash
if [[ "\$(whoami)" == "root" ]]; then
    sudo=""
else
    sudo="sudo"
fi
PREFIX="'"$PREFIX"'"
SCRIPT_LIST="'"$SCRIPT_LIST"'"
read -n 1 -p "This will uninstall bitcoin-scripts from \$PREFIX. Are you sure? (y/N) "
echo ""
if [[ \${REPLY} =~ y|Y ]]; then
    for script in \$SCRIPT_LIST; do
        echo -n "Uninstalling bc-\$script..."
        \$sudo unlink /usr/local/bin/bc-\$script
        echo ""
    done
    echo "Clean up rest..."
    \$sudo rm -rf "\$PREFIX" 2> /dev/null
    echo "Done."
fi
EOF'
$sudo chmod +x "$PREFIX/bc-scripts-uninstall.sh"
$sudo ln -f -s "$PREFIX/bc-scripts-uninstall.sh" /usr/local/sbin/bc-scripts-uninstall

echo "Done."
