#!/usr/bin/env bash
#
# install-persistent-wg.sh -- make the split VPN apply automatically to a
# WireGuard profile, the way install-persistent.sh does for OpenVPN.
#
# A WireGuard client profile with AllowedIPs = 0.0.0.0/0 makes wg-quick route
# every packet on the machine into the tunnel, including the replies of the SSH
# and RDP sessions you are connected through, so both freeze. The patched copy
# stops that:
#
#   Table = off   wg-quick adds no routes and no policy rules at all.
#   FwMark        marks WireGuard's own encrypted UDP packets 0xca6c, and a
#                 PostUp rule lets that mark skip the per-user MARK rule.
#                 WireGuard encrypts in the kernel but keeps the socket of the
#                 process that sent the inner packet, so without this its UDP
#                 still matches --uid-owner, is routed back into the tunnel
#                 and loops, wrapped again on every pass. OpenVPN never hit
#                 this because its daemon runs as root.
#   PostUp        vpn-split-up.sh routes only one user's traffic into the
#                 tunnel (fwmark + its own routing table + masquerade).
#   PreDown       vpn-split-down.sh removes those rules again.
#   PostUp        also routes the VPN's own range (WG_ROUTES, default
#                 10.8.0.0/16) through the tunnel in the main table, so every
#                 user can still reach the other peers. Table = off would
#                 otherwise leave only the routed user able to reach them.
#   DNS           removed, so the machine's resolver is left alone.
#   Keepalive     raised to 25 when missing or 0, so peers behind the server
#                 can still reach this machine once the NAT mapping expires.
#
# AllowedIPs is kept as it is: with Table = off it no longer changes routing,
# it only tells WireGuard which destinations it may carry for that peer, and a
# full exit needs 0.0.0.0/0 there.
#
# For each profile it writes <name>.split.conf beside it (mode 600), then
# RENAMES the original to bak.<name>.conf, so the unpatched profile cannot be
# brought up by accident. Files that are not WireGuard profiles (no
# [Interface] section, for example vpn-split.conf) are skipped.
#
# wg-quick names the interface after the file, and Linux allows at most 15
# characters, so <name>.split must fit: keep <name> to 9 characters or fewer.
#
# The OpenVPN profiles use mark 0x2 / table 200; these default to 0x3 / 201 so
# the two never share rules. Still run only one split VPN at a time: both down
# scripts remove the shared SSH safeguard and the IPv6 block for the user.
#
# Usage:
#   ./install-persistent-wg.sh                        # all plain *.conf here
#   ./install-persistent-wg.sh ~/Downloads/biker.conf # only these
#
# Environment overrides: WG_FW_MARK (default 0x3), WG_RT_TABLE (default 201),
# WG_ROUTES (space-separated, default "10.8.0.0/16"; set it empty for none).
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UP="$DIR/vpn-split-up.sh"
DOWN="$DIR/vpn-split-down.sh"
MARK="${WG_FW_MARK:-0x3}"
TABLE="${WG_RT_TABLE:-201}"
ROUTES="${WG_ROUTES-10.8.0.0/16}"
# The mark wg-quick itself uses; any value other than FW_MARK works.
WG_OWN_MARK="0xca6c"

# Resolve the user to bake into each profile. wg-quick runs PostUp as root, and
# under systemd there is no SUDO_USER, so the name has to live in the profile.
RUN_USER="${SUDO_USER:-${USER:-}}"
if [ -z "$RUN_USER" ] || [ "$RUN_USER" = "root" ]; then
    echo "Could not resolve a non-root user to route. Run this as that user." >&2
    exit 1
fi

declare -a SRC=()
if [ "$#" -gt 0 ]; then
    SRC=("$@")
else
    shopt -s nullglob
    SRC=("$DIR"/*.conf)
    shopt -u nullglob
fi

if [ "${#SRC[@]}" -eq 0 ]; then
    echo "No .conf files to process in $DIR" >&2
    exit 1
fi

patch_into() {
    # patch_into <source> <output>
    local src="$1" out="$2"
    local hooks="VPN_DEV=%i VPN_SPLIT_USER=$RUN_USER FW_MARK=$MARK RT_TABLE=$TABLE"

    # Drop the lines we own, then add ours right after [Interface].
    # PersistentKeepalive is rewritten in place, or appended after the peer's
    # other keys when the peer has none.
    local routes="" r
    for r in $ROUTES; do
        routes+="PostUp = ip route replace $r dev %i"$'\n'
    done

    # Let WireGuard's own packets past the per-user MARK rule (mangle, IPv4)
    # and past the per-user IPv6 REJECT (filter), in case the endpoint is IPv6.
    local m="-m mark --mark $WG_OWN_MARK"
    local own=""
    own+="FwMark = $WG_OWN_MARK"$'\n'
    own+="PostUp = iptables -t mangle -C OUTPUT $m -j RETURN 2>/dev/null || iptables -t mangle -I OUTPUT $m -j RETURN"$'\n'
    own+="PostUp = ip6tables -C OUTPUT $m -j ACCEPT 2>/dev/null || ip6tables -I OUTPUT $m -j ACCEPT"$'\n'
    local own_down=""
    own_down+="PostDown = iptables -t mangle -D OUTPUT $m -j RETURN 2>/dev/null || true"$'\n'
    own_down+="PostDown = ip6tables -D OUTPUT $m -j ACCEPT 2>/dev/null || true"$'\n'

    awk -v up="PostUp = $hooks $UP" -v down="PreDown = $hooks $DOWN" -v routes="$routes" \
        -v own="$own" -v own_down="$own_down" '
        function flush_peer() {
            if (in_peer && !peer_has_keepalive) print "PersistentKeepalive = 25"
            in_peer = 0; peer_has_keepalive = 0
        }
        /^[[:space:]]*\[/ {
            flush_peer()
            print
            if ($0 ~ /^[[:space:]]*\[Interface\]/) {
                print "Table = off"
                printf "%s", own
                printf "%s", routes
                print up
                print down
                printf "%s", own_down
            } else if ($0 ~ /^[[:space:]]*\[Peer\]/) {
                in_peer = 1
            }
            next
        }
        /^[[:space:]]*(Table|FwMark|DNS|PreUp|PostUp|PreDown|PostDown)[[:space:]]*=/ { next }
        /^[[:space:]]*PersistentKeepalive[[:space:]]*=/ {
            peer_has_keepalive = 1
            split($0, kv, "=")
            v = kv[2]; gsub(/[[:space:]]/, "", v)
            if (v == "" || v == "0" || v == "off") { print "PersistentKeepalive = 25"; next }
        }
        { print }
        END { flush_peer() }
    ' "$src" > "$out"
    chmod 600 "$out"
}

echo "Scripts referenced:"
echo "  PostUp  $UP"
echo "  PreDown $DOWN"
echo "  user $RUN_USER, mark $MARK, table $TABLE"
echo "  routes for everyone: ${ROUTES:-none}"
echo

for src in "${SRC[@]}"; do
    if [ ! -f "$src" ]; then
        echo "skip (not found): $src" >&2
        continue
    fi
    base="$(basename "$src")"

    case "$base" in
        bak.*.conf|*.split.conf)
            echo "skip (already processed): $base" >&2
            continue ;;
    esac

    if ! grep -qE '^[[:space:]]*\[Interface\]' "$src"; then
        echo "skip (not a WireGuard profile): $base" >&2
        continue
    fi

    name="${base%.conf}"
    iface="$name.split"
    if [ "${#iface}" -gt 15 ] || ! [[ "$iface" =~ ^[a-zA-Z0-9_=+.-]+$ ]]; then
        echo "skip ($iface is not a valid interface name; rename the file to 9 characters or fewer): $base" >&2
        continue
    fi

    srcdir="$(cd "$(dirname "$src")" && pwd)"
    out="$srcdir/$iface.conf"
    bak="$srcdir/bak.$name.conf"

    if [ -e "$bak" ]; then
        echo "skip ($(basename "$bak") already exists): $base" >&2
        continue
    fi

    patch_into "$src" "$out"
    mv "$src" "$bak"
    chmod 600 "$bak"
    echo "patched: $base  ->  $(basename "$out")"
    echo "  original moved to: $(basename "$bak")"
done

echo
echo "Bring a patched profile up as root:"
echo "  sudo wg-quick up <dir>/<name>.split.conf"
echo "Keep it up across reboots:"
echo "  sudo install -m 600 <dir>/<name>.split.conf /etc/wireguard/"
echo "  sudo systemctl enable --now wg-quick@<name>.split"
