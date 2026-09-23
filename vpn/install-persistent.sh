#!/usr/bin/env bash
#
# install-persistent.sh -- make the split VPN apply automatically.
#
# For each OpenVPN profile it patches, it writes a split-tunnel copy named
# <name>.split.ovpn (with the routing hooks and any redirect-gateway commented
# out), then RENAMES the original to bak.<name>.ovpn. The plain <name>.ovpn no
# longer exists afterwards, so you cannot accidentally start the non-split
# version with `sudo openvpn --config <name>.ovpn`.
#
# With no arguments it processes every plain *.ovpn in this directory, skipping
# files it already produced (bak.*.ovpn) or generated (*.split.ovpn), so it is
# safe to re-run. Pass explicit paths to process only those.
#
# Usage:
#   ./install-persistent.sh                 # all plain *.ovpn here
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
        base="$(basename "$f")"
        # Skip our own backups and generated split copies.
        case "$base" in
            bak.*.ovpn)   continue ;;
            *.split.ovpn) continue ;;
        esac
        SRC+=("$f")
    done
    shopt -u nullglob
fi

if [ "${#SRC[@]}" -eq 0 ]; then
    echo "No plain .ovpn files to process in $DIR" >&2
    exit 1
fi

patch_into() {
    # patch_into <source> <output>
    local src="$1" out="$2"
    cp "$src" "$out"

    add_line() {
        grep -qF -- "$1" "$out" || printf '%s\n' "$1" >> "$out"
    }

    # Comment out any full-tunnel directive in the copy.
    sed -i -E 's/^([[:space:]]*)(redirect-gateway[[:space:]].*)$/\1#\2/' "$out"

    add_line "script-security 2"
    add_line "route-up $UP"
    add_line "down $DOWN"
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
    base="$(basename "$src")"

    # Refuse to process a backup or an already-split file even if named on the
    # command line, so we never double-edit.
    case "$base" in
        bak.*.ovpn|*.split.ovpn)
            echo "skip (already processed): $base" >&2
            continue ;;
    esac

    name="${base%.ovpn}"
    srcdir="$(cd "$(dirname "$src")" && pwd)"
    out="$srcdir/$name.split.ovpn"
    bak="$srcdir/bak.$name.ovpn"

    if [ -e "$bak" ]; then
        echo "skip ($(basename "$bak") already exists): $base" >&2
        continue
    fi

    patch_into "$src" "$out"
    mv "$src" "$bak"
    echo "patched: $base  ->  $(basename "$out")"
    echo "  original moved to: $(basename "$bak")"
done

echo
echo "Run a patched profile as root:"
echo "  sudo openvpn --config $DIR/<name>.split.ovpn"
