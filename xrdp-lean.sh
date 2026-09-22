#!/bin/bash
# Squeeze the last bit of RDP latency out of a GPU-less VPS (xrdp 0.10, KDE Plasma 5 X11).
# Run: sudo ./xrdp-lean.sh [desktop-user]
#
# This script does NOT restart xrdp. Kernel settings apply at once; xrdp.ini, sesman.ini,
# the systemd drop-ins and startwm.sh apply after:
#   log out of the RDP session, then: sudo systemctl daemon-reload && sudo systemctl restart xrdp
# The KDE settings apply at the next Plasma login.
#
# Every edited file gets a .pre-lean backup (only on the first run).
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi
DESKTOP_USER=${1:-${SUDO_USER:-}}
if [ -z "$DESKTOP_USER" ] || ! id "$DESKTOP_USER" >/dev/null 2>&1; then
  echo "Desktop user not found. Pass it as the first argument." >&2
  exit 1
fi
USER_HOME=$(getent passwd "$DESKTOP_USER" | cut -d: -f6)
as_user() { sudo -u "$DESKTOP_USER" HOME="$USER_HOME" "$@"; }

cp -n /etc/xrdp/xrdp.ini   /etc/xrdp/xrdp.ini.pre-lean
cp -n /etc/xrdp/sesman.ini /etc/xrdp/sesman.ini.pre-lean
cp -n /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.pre-lean

echo "== 1. Channels: keep clipboard (cliprdr) and drdynvc (GFX runs over it), drop the rest"
# rdpdr = client drive/printer redirection, rdpsnd = audio, rail = RemoteApp, xrdpvr = video.
sed -i -E '/^\[Channels\]/,/^\[/{
  s/^rdpdr=.*/rdpdr=false/
  s/^rdpsnd=.*/rdpsnd=false/
  s/^rail=.*/rail=false/
  s/^xrdpvr=.*/xrdpvr=false/
}' /etc/xrdp/xrdp.ini

echo "== 2. CPU priority: encoder (xrdp) and X server ahead of the desktop"
# The RFX/H.264 encoder runs inside the xrdp connection process: nice -10.
# sesman spawns Xorg and chansrv, which inherit its nice -5. startwm.sh then puts the
# desktop back to nice 0 (a process may always raise its own niceness), so Plasma never
# competes with the encoder or the X server at equal priority.
mkdir -p /etc/systemd/system/xrdp.service.d /etc/systemd/system/xrdp-sesman.service.d
printf '[Service]\nNice=-10\n' > /etc/systemd/system/xrdp.service.d/nice.conf
printf '[Service]\nNice=-5\n'  > /etc/systemd/system/xrdp-sesman.service.d/nice.conf

echo "== 6. No screen blanking / DPMS in the session (no full redraw after idle)"
echo "   (also the nice reset from step 2, both in startwm.sh)"
if ! grep -q 'xrdp-lean' /etc/xrdp/startwm.sh; then
  sed -i '/^exec /i \
# xrdp-lean: desktop at nice 0 (Xorg/chansrv keep -5 from sesman); no blanking, no DPMS.\
renice -n 0 -p $$ >/dev/null 2>&1 || true\
xset s off -dpms >/dev/null 2>&1 || true\
' /etc/xrdp/startwm.sh
fi

echo "== 3. fq qdisc (native BBR pacing) - live, no restart needed"
cat > /etc/sysctl.d/92-xrdp-lean.conf <<'SYS'
net.core.default_qdisc=fq
SYS
sysctl -p /etc/sysctl.d/92-xrdp-lean.conf
for dev in $(ip -o link show up | awk -F': ' '$2 != "lo" && $2 !~ /^tun/ {print $2}'); do
  tc qdisc replace dev "$dev" root fq && echo "   $dev: fq"
done

echo "== 4. TLS: prefer AES-128-GCM (AES-NI, cheapest per frame)"
# TLS 1.2 stays enabled: the Android Windows App is not guaranteed to speak TLS 1.3.
# To try 1.3 only (faster handshake, nothing per frame):  ssl_protocols=TLSv1.3
sed -i -E 's/^#?tls_ciphers=.*/tls_ciphers=ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384/' /etc/xrdp/xrdp.ini

echo "== 5. Log level WARNING (xrdp, sesman, chansrv)"
sed -i -E '/^\[Logging\]/,/^\[/{ s/^LogLevel=.*/LogLevel=WARNING/ }' /etc/xrdp/xrdp.ini
sed -i -E '/^\[(Logging|ChansrvLogging)\]/,/^\[/{ s/^LogLevel=.*/LogLevel=WARNING/ }' /etc/xrdp/sesman.ini

echo "== 7. Send buffer 4 MB -> 512 KB (experimental: less stale-frame queue on a slow link)"
sed -i -E 's/^tcp_send_buffer_bytes=.*/tcp_send_buffer_bytes=524288/' /etc/xrdp/xrdp.ini

echo "== 8. Frame interval 16 ms -> 8 ms (experimental: ~120 fps cap for 120 Hz phones)"
sed -i -E 's/^(h264|rfx)_frame_interval=.*/\1_frame_interval=8/' /etc/xrdp/xrdp.ini

echo "== 11. KDE: remaining KWin effects off, no window shadows, no tooltips/notification animation"
kw() { as_user kwriteconfig5 "$@"; }
for e in dialogparent dimscreen frozenapp fullscreen login logout maximize morphingpopups windowaperture; do
  kw --file kwinrc --group Plugins --key "kwin4_effect_${e}Enabled" false
done
for e in highlightwindow kscreen presentwindows screenedge zoom; do
  kw --file kwinrc --group Plugins --key "${e}Enabled" false
done
kw --file breezerc --group Common --key ShadowSize ShadowNone
kw --file breezerc --group Common --key OutlineCloseButton false
kw --file breezerc --group Style --key AnimationsEnabled false
kw --file kdeglobals --group KDE --key AnimationDurationFactor 0
kw --file kdeglobals --group KDE --key CursorBlinkRate 0
kw --file plasmarc --group PlasmaToolTips --key Delay -1
kw --file krunnerrc --group General --key FreeFloating false
kw --file klaunchrc --group BusyCursorSettings --key Bouncing false
kw --file klaunchrc --group FeedbackStyle --key BusyCursor false
kw --file klaunchrc --group FeedbackStyle --key TaskbarButton false

echo
echo "Kernel and KDE settings written. xrdp changes are staged, NOT active yet."
echo "Next, from an SSH shell, after logging out of the RDP session:"
echo "  sudo systemctl daemon-reload && sudo systemctl restart xrdp"
echo "Then reconnect and verify:"
echo "  ps -o pid,ni,comm -C xrdp,Xorg,xrdp-chansrv,plasmashell     # expect -10 / -5 / -5 / 0"
echo "  tc qdisc show dev eth0 | head -1                              # expect fq"
echo "Rollback: restore /etc/xrdp/*.pre-lean, delete the nice.conf drop-ins and"
echo "  /etc/sysctl.d/92-xrdp-lean.conf, then daemon-reload + restart xrdp."
