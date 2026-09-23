#!/usr/bin/env bash
#
# vpn-split-up.sh -- route one user's traffic through the VPN.
#
# Apply the split-tunnel routing rules. Run this AFTER the OpenVPN
# tunnel is already up (the tun device must exist). It is idempotent:
# running it twice does no harm.
#
# Usage:  sudo ~/xrdp-tune/vpn/vpn-split-up.sh
#
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$DIR/vpn-split.conf"

# Resolve which user to route (safe under 'set -u'). Priority:
#   1. VPN_USER set in vpn-split.conf
#   2. VPN_SPLIT_USER exported by the .ovpn via 'setenv' (persistent hook)
#   3. SUDO_USER (the human behind sudo, for manual runs)
#   4. USER
if [ -z "${VPN_USER:-}" ]; then
    VPN_USER="${VPN_SPLIT_USER:-${SUDO_USER:-${USER:-}}}"
fi
if [ -z "$VPN_USER" ] || [ "$VPN_USER" = "root" ]; then
    echo "Cannot resolve a non-root user to route. Set VPN_USER in vpn-split.conf." >&2
    exit 1
fi


if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root (use sudo)." >&2
    exit 1
fi

# Resolve the numeric user id once; routing rules match on the id.
UID_NUM="$(id -u "$VPN_USER")"

# The tunnel interface must be present before we can route into it.
if ! ip link show "$VPN_DEV" >/dev/null 2>&1; then
    echo "Interface $VPN_DEV not found. Start the VPN first." >&2
    exit 1
fi

# 1. Routing table whose default route points into the tunnel.
ip route replace default dev "$VPN_DEV" table "$RT_TABLE"

# 2. Policy rule: packets carrying our firewall mark use that table.
ip rule show | grep -q "fwmark $FW_MARK lookup $RT_TABLE" \
    || ip rule add fwmark "$FW_MARK" table "$RT_TABLE"

# SSH lockout safeguard: never mark packets that sshd sends back to a
# client (source port 22). This keeps your remote session alive on the
# real link even when the marked user is your own login account.
iptables -t mangle -C OUTPUT -p tcp --sport 22 -j RETURN 2>/dev/null \
    || iptables -t mangle -I OUTPUT -p tcp --sport 22 -j RETURN

# 3. Mark every packet the VPN user sends.
iptables -t mangle -C OUTPUT -m owner --uid-owner "$UID_NUM" -j MARK --set-mark "$FW_MARK" 2>/dev/null \
    || iptables -t mangle -A OUTPUT -m owner --uid-owner "$UID_NUM" -j MARK --set-mark "$FW_MARK"

# 4. Rewrite the source address to the tunnel IP on the way out,
#    otherwise the VPN server drops packets that still carry the
#    machine's normal (eth0) address.
iptables -t nat -C POSTROUTING -o "$VPN_DEV" -j MASQUERADE 2>/dev/null \
    || iptables -t nat -A POSTROUTING -o "$VPN_DEV" -j MASQUERADE

# 5. Block IPv6 for the VPN user. The VPN carries IPv4 only, so any
#    IPv6 request would leak straight out over the normal connection
#    and expose the real address. Reject it instead.
ip6tables -C OUTPUT -m owner --uid-owner "$UID_NUM" -j REJECT 2>/dev/null \
    || ip6tables -A OUTPUT -m owner --uid-owner "$UID_NUM" -j REJECT

# 6. Loosen reverse-path filtering so asymmetric tunnel replies are
#    not dropped.
sysctl -q -w net.ipv4.conf.all.rp_filter=2
sysctl -q -w "net.ipv4.conf.$VPN_DEV.rp_filter=2" 2>/dev/null || true

echo "Split VPN active. Traffic from user '$VPN_USER' now exits via $VPN_DEV."
echo "Verify:  sudo -u $VPN_USER curl -s ifconfig.me; echo"
