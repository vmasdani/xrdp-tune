#!/bin/bash
# One-shot install on a fresh Ubuntu 24.04 server without a GPU:
#   xrdp-setup.sh   KDE Plasma X11 + xrdp/xorgxrdp 0.10 from source, GFX, TCP buffers
#   xrdp-snappy.sh  BBR, notsent_lowat, 60 fps frame interval
#   xrdp-lean.sh    channels, priority, fq, TLS, logging, KDE trims (frame interval 8 ms)
#   xrdp-ugly.sh    looks for latency: flat dark theme, 1-bit fonts, plain cursor, no notifications
#   xrdp-flameshot.sh  flameshot screenshots on Ctrl+Alt+Shift+P
#   xrdp-zram.sh    compressed swap in RAM (zram, zstd, size = RAM), disk swap as overflow
# then one xrdp start at the end.
#
# Usage: sudo ./install.sh [desktop-user]
set -euo pipefail
cd "$(dirname "$0")"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi
DESKTOP_USER=${1:-${SUDO_USER:-}}

export NO_RESTART=1
./xrdp-setup.sh "$DESKTOP_USER"
./xrdp-snappy.sh
./xrdp-lean.sh "$DESKTOP_USER"
./xrdp-ugly.sh "$DESKTOP_USER"
./xrdp-flameshot.sh "$DESKTOP_USER"
./xrdp-zram.sh

echo "== Starting xrdp"
systemctl daemon-reload
systemctl restart xrdp
sleep 2
systemctl --no-pager --lines=3 status xrdp xrdp-sesman || true
echo
echo "Done. Connect to port 3389, session type Xorg. See README.md for checks and rollback."
cat <<EOF

== SECURITY WARNING
Do not expose xrdp (port 3389) directly to the internet on a public VPS.
Tunnel RDP over SSH instead, which is more secure: block 3389 in the VPS
firewall / provider security group and keep only SSH (22) open.

Windows App on Android, through Termux:
  1. In Termux: pkg install openssh
  2. Save this as ~/rdp.sh, chmod +x ~/rdp.sh, then run ./rdp.sh and leave it open:
       ssh -N -L 3389:127.0.0.1:3389 ${DESKTOP_USER:-username}@<vps-ip>
  3. In Windows App, add a PC at 127.0.0.1:3389 (not the VPS IP).
See "Security: RDP over SSH" in README.md.
EOF
