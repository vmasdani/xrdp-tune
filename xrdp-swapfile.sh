#!/bin/bash
# Disk swapfile as overflow behind zram (or as plain swap without zram).
# Run: sudo ./xrdp-swapfile.sh [size-gb]         (default: half of RAM, 2 to 8 GB)
#      sudo ./xrdp-swapfile.sh --add [size-gb]   (extra swapfile next to an active disk swap)
#
# Never restarts xrdp, no reboot needed. Without --add it does nothing if a disk swap is
# already active or /swapfile already exists. With --add it creates the first free name of
# /swapfile, /swapfile2, /swapfile3, ... An existing swap is never resized or removed.
# Rollback: sudo swapoff <file>; remove the <file> line from /etc/fstab; rm <file>
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

RAM_MB=$(awk '/^MemTotal:/ {printf "%d", $2 / 1024}' /proc/meminfo)
DEFAULT_GB=$(( (RAM_MB / 2 + 512) / 1024 )); [ "$DEFAULT_GB" -lt 2 ] && DEFAULT_GB=2; [ "$DEFAULT_GB" -gt 8 ] && DEFAULT_GB=8
ADD=0
if [ "${1:-}" = "--add" ]; then ADD=1; shift; fi
SIZE_GB=${1:-$DEFAULT_GB}
SWAPFILE=/swapfile

EXISTING=$(awk 'NR > 1 && $1 !~ /^\/dev\/zram/ {print $1}' /proc/swaps)
if [ "$ADD" = 1 ]; then
  n=2
  while [ -e "$SWAPFILE" ] || grep -q "^$SWAPFILE " /etc/fstab; do
    SWAPFILE=/swapfile$n
    n=$(( n + 1 ))
  done
fi

echo "== Disk swapfile: $SIZE_GB GB at $SWAPFILE"
if [ -n "$EXISTING" ] && [ "$ADD" = 0 ]; then
  echo "   Disk swap already active, kept as is: $EXISTING"
  echo "   Use --add for an extra swapfile next to it."
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
