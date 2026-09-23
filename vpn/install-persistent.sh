#!/usr/bin/env bash
#
# install-persistent.sh -- make the split VPN apply automatically.
#
# Patch OpenVPN profiles so the routing rules are installed every time the
# tunnel connects and removed when it disconnects. After this, you never run
# vpn-split-up.sh by hand for those profiles.
#
# With no arguments, it patches every *.ovpn file in this directory and writes
# a patched copy named <name>.split.ovpn next to it (the original is left
# untouched). Pass explicit paths to patch only those instead.
#
# Usage:
#   ./install-persistent.sh                 # all *.ovpn in this folder
#   ./install-persistent.sh a.ovpn b.ovpn   # only these
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UP="$DIR/vpn-split-up.sh"
DOWN="$DIR/vpn-split-down.sh"

# Build the list of source profiles.
declare -a SRC=()
if [ "$#" -gt 0 ]; then
    SRC=("$@")
else
    shopt -s nullglob
    for f in "$DIR"/*.ovpn; do
        # Skip files this script produced, so re-running is safe.
        case "$f" in
            *.split.ovpn) continue ;;
        esac
        SRC+=("$f")
    done
    shopt -u nullglob
fi

if [ "${#SRC[@]}" -eq 0 ]; then
    echo "No .ovpn files found in $DIR" >&2
    exit 1
fi

patch_one() {
    local src="$1" out="$2"
    cp "$src" "$out"

    add_line() {
        # Append a directive only if it is not present already.
        grep -qF -- "$1" "$out" || printf '%s\n' "$1" >> "$out"
    }

    # Neutralise any full-tunnel line: comment it out in the copy so it cannot
    # hijack the default route and lock out SSH.
    sed -i -E 's/^([[:space:]]*)(redirect-gateway[[:space:]].*)$/\1#\2/' "$out"

    # script-security 2 lets OpenVPN run our helper scripts.
    add_line "script-security 2"
    # route-up runs after the tunnel routes are in place.
    add_line "route-up $UP"
    # down runs on disconnect to clean the rules up.
    add_line "down $DOWN"
    # Ignore any server push that would grab the whole default route.
    add_line 'pull-filter ignore "redirect-gateway"'
}

echo "Scripts referenced:"
echo "  route-up $UP"
echo "  down     $DOWN"
echo

for src in "${SRC[@]}"; do
    if [ ! -f "$src" ]; then
        echo "skip (not found): $src" >&2
        continue
    fi
    # Output name: strip a trailing .ovpn, add .split.ovpn, keep it in DIR.
    base="$(basename "$src")"
    base="${base%.ovpn}"
    out="$DIR/$base.split.ovpn"
    patch_one "$src" "$out"
    echo "patched: $src  ->  $out"
done

echo
echo "Run a patched profile as root so the hooks have permission:"
echo "  sudo openvpn --config $DIR/<name>.split.ovpn"
