#!/usr/bin/env bash
#
# wg-fg.sh -- run a WireGuard profile in the foreground, like
# `sudo openvpn --config <profile>`.
#
# wg-quick brings the tunnel up and returns at once; the tunnel then lives in
# the kernel until someone runs `wg-quick down`. This wrapper instead holds the
# terminal: it brings the profile up, prints the handshake and transfer every
# 30 seconds, and brings the profile down again on Ctrl-C, on kill, or when the
# terminal closes. Use a patched <name>.split.conf so the split-routing hooks
# run on the way up and down.
#
# Usage:  sudo ~/xrdp-tune/vpn/wg-fg.sh ~/xrdp-tune/vpn/biker.split.conf
#
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: sudo $0 <profile.conf>" >&2
    exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root (use sudo)." >&2
    exit 1
fi

CONF="$(realpath "$1")"
IFACE="$(basename "$CONF" .conf)"

# Bring it up before installing the trap: if this fails (bad profile, or the
# interface already exists) there is nothing of ours to take down.
wg-quick up "$CONF"

cleanup() {
    trap - INT TERM HUP EXIT
    set +e
    # After a hangup the terminal is gone and every write fails. wg-quick runs
    # under set -e, so a failed write could abort it halfway through the
    # teardown; send its output nowhere instead.
    if [ "${1:-}" = hup ]; then
        exec >/dev/null 2>&1
    fi
    echo
    wg-quick down "$CONF"
    # Exit here: bash would otherwise resume the loop after an INT/TERM handler.
    exit 0
}
trap cleanup INT TERM EXIT
trap 'cleanup hup' HUP

echo "Tunnel $IFACE up. Ctrl-C to disconnect."
while true; do
    # Sleep in the background and wait, so a signal interrupts at once instead
    # of after the sleep finishes.
    sleep 30 & wait $! || true

    if ! ip link show "$IFACE" >/dev/null 2>&1; then
        echo "Interface $IFACE disappeared (taken down elsewhere). Exiting."
        trap - INT TERM HUP EXIT
        exit 1
    fi

    now=$(date +%s)
    wg show "$IFACE" dump | tail -n +2 | while IFS=$'\t' read -r _ _ endpoint _ hs rx tx _; do
        if [ "$hs" -eq 0 ]; then age="never"; else age="$((now - hs))s ago"; fi
        printf '%s  endpoint %s  handshake %s  rx %s B  tx %s B\n' \
            "$(date +%H:%M:%S)" "$endpoint" "$age" "$rx" "$tx"
    done
done
