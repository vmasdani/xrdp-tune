#!/bin/bash
# Lower RDP input latency, mainly for mobile / Wi-Fi clients.
# Run: sudo ./xrdp-snappy.sh
# WARNING: the xrdp restart at the end also restarts xrdp-sesman (BindsTo=xrdp.service).
# The new sesman loses track of running X sessions, so they become orphaned and a reconnect
# starts a second Plasma session that hangs. Log out of the RDP session before running this.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

echo "== TCP latency tuning"
# tcp_notsent_lowat: keep little unsent data queued in the socket, so stale frames
#   do not pile up behind the 4 MB send buffer when the link slows down.
# tcp_slow_start_after_idle=0: no slow restart after a pause, so the first redraw is fast.
# bbr: copes better with lossy mobile links than cubic. Works with the fq_codel qdisc.
echo tcp_bbr > /etc/modules-load.d/tcp_bbr.conf
modprobe tcp_bbr
cat > /etc/sysctl.d/91-xrdp-latency.conf <<'EOF'
net.ipv4.tcp_notsent_lowat=16384
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl -p /etc/sysctl.d/91-xrdp-latency.conf

echo "== xrdp frame rate: RFX frame interval 32 ms -> 16 ms (about 30 -> 60 fps cap)"
cp -n /etc/xrdp/xrdp.ini /etc/xrdp/xrdp.ini.pre-snappy
sed -i -E 's/^rfx_frame_interval=.*/rfx_frame_interval=16/' /etc/xrdp/xrdp.ini
grep -nE '^(h264|rfx|normal)_frame_interval' /etc/xrdp/xrdp.ini

if [ "${NO_RESTART:-0}" = 1 ]; then
  echo "== NO_RESTART=1: xrdp not restarted, changes apply at the next restart"
else
  echo "== Restarting xrdp and xrdp-sesman (orphans running RDP sessions)"
  systemctl restart xrdp
  systemctl is-active xrdp
fi
