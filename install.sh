#!/bin/bash
# One-shot install on a fresh Ubuntu 24.04 server without a GPU:
#   xrdp-setup.sh   KDE Plasma X11 + xrdp/xorgxrdp 0.10 from source, GFX, TCP buffers
#   xrdp-snappy.sh  BBR, notsent_lowat, 60 fps frame interval
#   xrdp-lean.sh    channels, priority, fq, TLS, logging, KDE trims (frame interval 8 ms)
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

echo "== Starting xrdp"
systemctl daemon-reload
systemctl restart xrdp
sleep 2
systemctl --no-pager --lines=3 status xrdp xrdp-sesman || true
echo
echo "Done. Connect to port 3389, session type Xorg. See README.md for checks and rollback."
