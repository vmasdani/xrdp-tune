#!/bin/bash
# One-shot install on a fresh Ubuntu 24.04 or 26.04 server without a GPU. Asks what to install,
# shows a review, and runs the chosen scripts only after a "y":
#   xrdp-swapfile.sh   disk swapfile (overflow behind zram)
#   xrdp-zram.sh       compressed swap in RAM (zram)
#   xrdp-setup.sh      KDE Plasma or Xfce (X11) + xrdp/xorgxrdp 0.10 (apt on 26.04, source on 24.04), GFX, TCP buffers (always)
#   xrdp-snappy.sh     BBR, notsent_lowat, 60 fps frame interval
#   xrdp-lean.sh       channels, priority, fq, TLS, logging, desktop trims (frame interval 8 ms)
#   xrdp-ugly.sh       looks for latency: flat dark theme, 1-bit fonts, plain cursor, no notifications
#   xrdp-flameshot.sh  flameshot screenshots on Ctrl+Alt+Shift+P
#   xrdp-brave.sh      Brave browser, policies and flags for a GPU-less desktop
#   xrdp-firefox.sh    or Firefox (.deb, not snap), policies for a GPU-less desktop
#   xrdp-litexl.sh     Lite XL editor (VS Code-like, light), no animations or cursor blink
# then one xrdp start at the end. Swap comes first so a source build of xrdp has memory to spare.
#
# Usage: sudo ./install.sh [desktop-user]       ask, review, confirm
#        sudo ./install.sh -y [desktop-user]    take every default, no questions
set -euo pipefail
cd "$(dirname "$0")"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi
ASSUME_YES=0
if [ "${1:-}" = "-y" ]; then ASSUME_YES=1; shift; fi
if [ "$ASSUME_YES" = 0 ] && [ ! -t 0 ]; then
  echo "No terminal for the questions. Run interactively, or use -y for the defaults." >&2
  exit 1
fi

# Recommended numbers, from this machine.
# zram works in MB: whole GB rounds a 512 MB box to 0 and then to a 1 GB floor (2x RAM).
RAM_MB=$(awk '/^MemTotal:/ {printf "%d", $2 / 1024}' /proc/meminfo)
REC_ZRAM_MB=$RAM_MB; [ "$REC_ZRAM_MB" -gt 16384 ] && REC_ZRAM_MB=16384           # = RAM, max 16 GB
REC_SWAP_GB=$(( (RAM_MB / 2 + 512) / 1024 ))                                     # RAM / 2,
[ "$REC_SWAP_GB" -lt 2 ] && REC_SWAP_GB=2; [ "$REC_SWAP_GB" -gt 8 ] && REC_SWAP_GB=8   # 2 to 8 GB
DISK_SWAP=$(awk 'NR > 1 && $1 !~ /^\/dev\/zram/ {printf "%s%s (%d MB)", s, $1, $3 / 1024; s = ", "}' /proc/swaps)

# ask_yn VAR "question" y|n
ask_yn() {
  local def=$3 hint ans
  [ "$def" = y ] && hint="Y/n" || hint="y/N"
  if [ "$ASSUME_YES" = 1 ]; then printf -v "$1" %s "$def"; return; fi
  while true; do
    read -r -p "$2 [$hint]: " ans
    ans=${ans:-$def}
    case "${ans,,}" in
      y|yes) printf -v "$1" y; return ;;
      n|no)  printf -v "$1" n; return ;;
    esac
  done
}
# ask_num VAR "question" default
ask_num() {
  local ans
  if [ "$ASSUME_YES" = 1 ]; then printf -v "$1" %s "$3"; return; fi
  while true; do
    read -r -p "$2 [$3]: " ans
    ans=${ans:-$3}
    if [[ "$ans" =~ ^[1-9][0-9]*$ ]]; then printf -v "$1" %s "$ans"; return; fi
    echo "   Whole number, please."
  done
}
# ask_pick VAR "question" default-number option1 option2 ...
ask_pick() {
  local var=$1 q=$2 def=$3 i ans; shift 3
  if [ "$ASSUME_YES" = 1 ]; then printf -v "$var" %s "${!def}"; return; fi
  echo "$q"
  for i in $(seq 1 $#); do echo "   $i) ${!i}"; done
  while true; do
    read -r -p "   Pick [$def]: " ans
    ans=${ans:-$def}
    if [[ "$ans" =~ ^[0-9]+$ ]] && [ "$ans" -ge 1 ] && [ "$ans" -le $# ]; then
      printf -v "$var" %s "${!ans}"; return
    fi
  done
}

echo "== xrdp-tune installer"
echo "   This machine: ${RAM_MB} MB RAM, $(nproc) CPUs, disk swap: ${DISK_SWAP:-none}"
echo

DESKTOP_USER=${1:-${SUDO_USER:-}}
if [ "$ASSUME_YES" = 0 ]; then
  read -r -p "Desktop user [${DESKTOP_USER}]: " ans
  DESKTOP_USER=${ans:-$DESKTOP_USER}
fi
if [ -z "$DESKTOP_USER" ] || ! id "$DESKTOP_USER" >/dev/null 2>&1; then
  echo "Desktop user '$DESKTOP_USER' not found." >&2
  exit 1
fi

ask_pick DESKTOP "Desktop:" 1 "KDE Plasma, X11 (recommended)" \
  "Xfce, X11 (lighter, wireframe window drag)"
DESKTOP=${DESKTOP%% (*}
case "$DESKTOP" in
  Xfce*) XRDP_DESKTOP=xfce ;;
  *)     XRDP_DESKTOP=kde ;;
esac
ask_yn DO_SNAPPY    "Network latency tuning: BBR, 60 fps (xrdp-snappy.sh, recommended)" y
ask_yn DO_LEAN      "Lean tuning: priorities, fq, channels, desktop effects off (xrdp-lean.sh, recommended)" y
ask_yn DO_UGLY      "Flat dark look for latency (xrdp-ugly.sh, recommended)" y
ask_yn DO_FLAMESHOT "Flameshot on Ctrl+Alt+Shift+P (xrdp-flameshot.sh, recommended)" y
ask_pick BROWSER "Browser, tuned for no GPU:" 1 "Brave (xrdp-brave.sh, recommended)" \
  "Firefox (xrdp-firefox.sh, .deb from Mozilla, not the snap)" "None"
BROWSER=${BROWSER%% (*}
ask_yn DO_LITEXL    "Lite XL editor, light VS Code-like (xrdp-litexl.sh, recommended)" y

ask_yn DO_ZRAM "zram: compressed swap in RAM (recommended)" y
if [ "$DO_ZRAM" = y ]; then
  ask_num ZRAM_MB "   zram size in MB (recommended $REC_ZRAM_MB = RAM)" "$REC_ZRAM_MB"
  ask_pick ZRAM_ALGO "   zram compression:" 1 "zstd (recommended, ~3:1)" "lz4 (less CPU, ~2:1)"
  ZRAM_ALGO=${ZRAM_ALGO%% *}
fi

if [ -n "$DISK_SWAP" ]; then
  # The existing swap is never touched; an extra swapfile can go next to it.
  # Recommended extra = RAM / 2 minus what is already there; none when that is enough.
  DISK_SWAP_MB=$(awk 'NR > 1 && $1 !~ /^\/dev\/zram/ {s += $3} END {printf "%d", s / 1024}' /proc/swaps)
  REC_ADD_GB=$(( REC_SWAP_GB - (DISK_SWAP_MB + 512) / 1024 ))
  echo "Disk swap: already active ($DISK_SWAP), kept as is."
  if [ "$REC_ADD_GB" -ge 1 ]; then
    ask_yn ADD_SWAP "   Add an extra swapfile next to it (recommended, total below RAM / 2)" y
  else
    REC_ADD_GB=2
    ask_yn ADD_SWAP "   Add an extra swapfile next to it (not needed, already RAM / 2 or more)" n
  fi
  DO_SWAP=keep
  if [ "$ADD_SWAP" = y ]; then
    DO_SWAP=add
    ask_num SWAP_GB "   Extra swapfile size in GB" "$REC_ADD_GB"
  fi
else
  ask_yn DO_SWAP "Disk swapfile as overflow (recommended)" y
  if [ "$DO_SWAP" = y ]; then
    ask_num SWAP_GB "   Swapfile size in GB (recommended $REC_SWAP_GB = RAM / 2, 2 to 8)" "$REC_SWAP_GB"
  fi
fi

yn() { [ "$1" = y ] && echo yes || echo no; }
echo
echo "== Review"
echo "   Desktop user   $DESKTOP_USER"
echo "   Desktop        $DESKTOP + xrdp 0.10 (Ubuntu package on 26.04+, else built from source)"
echo "   Snappy         $(yn "$DO_SNAPPY")"
echo "   Lean           $(yn "$DO_LEAN")"
echo "   Flat look      $(yn "$DO_UGLY")"
echo "   Flameshot      $(yn "$DO_FLAMESHOT")"
echo "   Browser        $BROWSER"
echo "   Lite XL        $(yn "$DO_LITEXL")"
if [ "$DO_ZRAM" = y ]; then
  echo "   zram           yes, $ZRAM_MB MB, $ZRAM_ALGO"
else
  echo "   zram           no"
fi
case "$DO_SWAP" in
  keep) echo "   Disk swap      keep existing ($DISK_SWAP)" ;;
  add)  echo "   Disk swap      keep existing ($DISK_SWAP) + extra $SWAP_GB GB swapfile" ;;
  y)    echo "   Disk swap      yes, /swapfile $SWAP_GB GB" ;;
  n)    echo "   Disk swap      no" ;;
esac
if [ "$DO_ZRAM" = n ] && [ "$DO_SWAP" = n ]; then
  echo "   Warning: no swap at all. A memory spike goes straight to the OOM killer."
fi
if [ "$XRDP_DESKTOP" = kde ] && [ "$RAM_MB" -lt 1800 ]; then
  echo "   Warning: ${RAM_MB} MB RAM is too little for KDE Plasma (about 1.2 GB on its own)."
  echo "   Expect constant swapping even with zram. 2 GB is the minimum, 4 GB is comfortable."
elif [ "$XRDP_DESKTOP" = xfce ] && [ "$RAM_MB" -lt 900 ]; then
  echo "   Warning: ${RAM_MB} MB RAM is tight even for Xfce. Expect swapping once a browser runs."
  echo "   2 GB is comfortable."
fi
echo "   On 24.04 this takes a while: it builds xrdp and xorgxrdp."
echo

ask_yn GO "Proceed?" n
if [ "$ASSUME_YES" = 1 ]; then GO=y; fi
if [ "$GO" != y ]; then
  echo "Nothing installed."
  exit 0
fi

export NO_RESTART=1 XRDP_DESKTOP
[ "$DO_SWAP" = y ]       && ./xrdp-swapfile.sh "$SWAP_GB"
[ "$DO_SWAP" = add ]     && ./xrdp-swapfile.sh --add "$SWAP_GB"
[ "$DO_ZRAM" = y ]       && ZRAM_SIZE=$ZRAM_MB ZRAM_ALGO=$ZRAM_ALGO ./xrdp-zram.sh
./xrdp-setup.sh "$DESKTOP_USER"
[ "$DO_SNAPPY" = y ]     && ./xrdp-snappy.sh
[ "$DO_LEAN" = y ]       && ./xrdp-lean.sh "$DESKTOP_USER"
[ "$DO_UGLY" = y ]       && ./xrdp-ugly.sh "$DESKTOP_USER"
[ "$DO_FLAMESHOT" = y ]  && ./xrdp-flameshot.sh "$DESKTOP_USER"
[ "$BROWSER" = Brave ]   && ./xrdp-brave.sh "$DESKTOP_USER"
[ "$BROWSER" = Firefox ] && ./xrdp-firefox.sh
[ "$DO_LITEXL" = y ]     && ./xrdp-litexl.sh "$DESKTOP_USER"

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
