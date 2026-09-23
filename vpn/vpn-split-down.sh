#!/usr/bin/env bash
#
# vpn-split-down.sh -- remove the split-tunnel routing rules.
#
# Undo everything vpn-split-up.sh added. Safe to run even if some
# rules are already gone.
#
# Usage:  sudo ~/xrdp-tune/vpn/vpn-split-down.sh
#
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$DIR/vpn-split.conf"

# Resolve which user to route. Empty VPN_USER means auto-detect the human
# behind the command: prefer $SUDO_USER, then $USER. Refuse root.
if [ -z "${VPN_USER:-}" ]; then
    VPN_USER="${SUDO_USER:-$USER}"
fi
if [ -z "$VPN_USER" ] || [ "$VPN_USER" = "root" ]; then
    # On teardown, do not abort: still remove the table and rule below,
    # just skip the per-user firewall rules we cannot resolve.
    VPN_USER=""
fi


if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root (use sudo)." >&2
    exit 1
fi

UID_NUM="$(id -u "$VPN_USER" 2>/dev/null || echo "")"

ip rule del fwmark "$FW_MARK" table "$RT_TABLE" 2>/dev/null || true
ip route flush table "$RT_TABLE" 2>/dev/null || true

if [ -n "$UID_NUM" ]; then
    iptables -t mangle -D OUTPUT -m owner --uid-owner "$UID_NUM" -j MARK --set-mark "$FW_MARK" 2>/dev/null || true
    ip6tables -D OUTPUT -m owner --uid-owner "$UID_NUM" -j REJECT 2>/dev/null || true
fi
iptables -t mangle -D OUTPUT -p tcp --sport 22 -j RETURN 2>/dev/null || true
iptables -t nat -D POSTROUTING -o "$VPN_DEV" -j MASQUERADE 2>/dev/null || true

echo "Split VPN rules removed."
