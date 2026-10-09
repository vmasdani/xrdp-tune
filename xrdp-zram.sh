#!/bin/bash
# Compressed swap in RAM (zram) so the 12 GB box holds more before touching the disk swapfile.
# Run: sudo ./xrdp-zram.sh
#
# Never restarts xrdp and needs no reboot: zram swap starts live. Pages already in the disk
# swapfile stay there until touched; to pull them back into RAM right away (needs that much
# free RAM):  sudo swapoff /swapfile && sudo swapon /swapfile
#
# Layout after this script:
#   /dev/zram0  zstd, size = RAM, priority 100  (used first)
#   /swapfile   priority -2, left as is          (overflow only, avoids an OOM cliff)
#   zswap       off (zswap in front of zram would compress every page twice)
#
# Rollback: sudo swapoff /dev/zram0; delete /etc/systemd/zram-generator.conf and
#   /etc/sysctl.d/99-zram.conf; sudo systemctl daemon-reload; sudo sysctl --system
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

ZRAM_SIZE=${ZRAM_SIZE:-ram}          # zram-generator expression, e.g. "ram / 2" or "8192" (MB)
ZRAM_ALGO=${ZRAM_ALGO:-zstd}         # zstd ~3:1, lz4 ~2:1 but cheaper on CPU

echo "== 1. Packages: zram module (linux-modules-extra) and systemd-zram-generator"
# Ubuntu cloud kernels (linux-virtual) leave zram.ko out; it lives in linux-modules-extra.
# linux-image-extra-virtual keeps the extras coming for every future kernel.
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y systemd-zram-generator linux-image-extra-virtual
if ! DEBIAN_FRONTEND=noninteractive apt-get install -y "linux-modules-extra-$(uname -r)"; then
  echo "   linux-modules-extra-$(uname -r) not available: zram starts after a reboot into the newest kernel."
fi

echo "== 2. zram-generator: /dev/zram0, $ZRAM_ALGO, size $ZRAM_SIZE, priority 100"
cat > /etc/systemd/zram-generator.conf <<EOF
# Written by xrdp-zram.sh
[zram0]
zram-size = $ZRAM_SIZE
compression-algorithm = $ZRAM_ALGO
swap-priority = 100
EOF

echo "== 3. Swap tuning for zram (overrides 99-swap.conf swappiness=10)"
# File name sorts after 99-swap.conf and 99-sysctl.conf, so these values win.
# swappiness 180: swapping to zram is cheaper than dropping page cache and rereading disk.
# page-cluster 0: read one page per fault; readahead buys nothing on RAM-backed swap.
# watermark_boost_factor 0 / watermark_scale_factor 125: steadier reclaim, fewer stalls.
cat > /etc/sysctl.d/99-zram.conf <<'EOF'
vm.swappiness=180
vm.page-cluster=0
vm.watermark_boost_factor=0
vm.watermark_scale_factor=125
EOF
sysctl -p /etc/sysctl.d/99-zram.conf

echo "== 4. zswap off (no double compression)"
echo 0 > /sys/module/zswap/parameters/enabled 2>/dev/null || true

echo "== 5. Start zram swap"
systemctl daemon-reload
if grep -q '^/dev/zram0 ' /proc/swaps; then
  echo "   /dev/zram0 already active. Config changes apply at next boot, or now with:"
  echo "   sudo swapoff /dev/zram0 && sudo systemctl restart systemd-zram-setup@zram0 dev-zram0.swap"
elif modprobe zram 2>/dev/null; then
  systemctl start dev-zram0.swap
else
  echo "   zram module not loadable on $(uname -r). Reboot, then zram starts on its own."
fi

echo
swapon --show
zramctl 2>/dev/null || true
echo
echo "Check later: zramctl  (DATA vs COMPR = real ratio), swapon --show (zram prio 100 first)."
