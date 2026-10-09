#!/bin/bash
# Disk swapfile as overflow behind zram (or as plain swap without zram).
# Run: sudo ./xrdp-swapfile.sh [size-gb]     (default: half of RAM, 2 to 8 GB)
#
# Never restarts xrdp, no reboot needed. Does nothing if a disk swap is already active or
# /swapfile already exists: an existing swap is kept as it is, never resized or removed.
# Rollback: sudo swapoff /swapfile; remove the /swapfile line from /etc/fstab; rm /swapfile
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

RAM_MB=$(awk '/^MemTotal:/ {printf "%d", $2 / 1024}' /proc/meminfo)
DEFAULT_GB=$(( (RAM_MB / 2 + 512) / 1024 )); [ "$DEFAULT_GB" -lt 2 ] && DEFAULT_GB=2; [ "$DEFAULT_GB" -gt 8 ] && DEFAULT_GB=8
SIZE_GB=${1:-$DEFAULT_GB}
SWAPFILE=/swapfile

echo "== Disk swapfile: $SIZE_GB GB at $SWAPFILE"
EXISTING=$(awk 'NR > 1 && $1 !~ /^\/dev\/zram/ {print $1}' /proc/swaps)
if [ -n "$EXISTING" ]; then
  echo "   Disk swap already active, kept as is: $EXISTING"
  exit 0
fi
if [ -e "$SWAPFILE" ]; then
  echo "   $SWAPFILE exists but is not active. Kept untouched; check it by hand."
  exit 0
fi

FREE_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
if [ "$FREE_GB" -lt $(( SIZE_GB + 2 )) ]; then
  echo "   Only $FREE_GB GB free on /, not enough for a $SIZE_GB GB swapfile. Skipped." >&2
  exit 1
fi

fallocate -l "${SIZE_GB}G" "$SWAPFILE" 2>/dev/null \
  || dd if=/dev/zero of="$SWAPFILE" bs=1M count=$(( SIZE_GB * 1024 )) status=none
chmod 600 "$SWAPFILE"
mkswap "$SWAPFILE" >/dev/null
swapon "$SWAPFILE"
grep -q "^$SWAPFILE " /etc/fstab || echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
swapon --show
