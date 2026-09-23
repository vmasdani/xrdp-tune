#!/bin/bash
# Browser access to the running xrdp desktop over H.264: xpra shadow server + HTML5 client.
# The xrdp session stays as it is. xpra mirrors its X display (:10 by default) and serves
# https://<host>:14500/ with password auth. Android Chrome decodes H.264 in hardware
# (WebCodecs), so this works around the Windows App's missing AVC decode.
#
# Usage: sudo ./xpra-shadow.sh              (desktop user = the user who ran sudo)
#        sudo ./xpra-shadow.sh someuser
# Environment overrides:
#   SHADOW_DISPLAY=:10    X display of the xrdp session (check with: ls /tmp/.X11-unix)
#   XPRA_PORT=14500       HTTPS/WSS port for the browser
#   REFRESH_RATE=30       screen polls per second (see note below)
#   SSL_CERT=/path SSL_KEY=/path   use a real certificate instead of a self-signed one
#
# No GPU: the X11 shadow backend has no damage events. It grabs the whole screen every
# 1/REFRESH_RATE s and hands it to the encoder, so CPU cost scales with this rate and the
# session resolution. 30 is a compromise; drop to 20 if xpra eats too much CPU.
#
# Result: xpra from the xpra.org repo (Ubuntu's own package is 3.1, too old for WebCodecs),
# systemd unit xpra-shadow.service running as the desktop user. The unit waits for the
# xrdp X display and restarts when the xrdp session ends and a new one starts.
# Never restarts xrdp.
set -euo pipefail

SHADOW_DISPLAY=${SHADOW_DISPLAY:-:10}
XPRA_PORT=${XPRA_PORT:-14500}
REFRESH_RATE=${REFRESH_RATE:-30}
CONF_DIR=/etc/xpra/shadow
DESKTOP_USER=${1:-${SUDO_USER:-}}

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi
if [ -z "$DESKTOP_USER" ] || ! id "$DESKTOP_USER" >/dev/null 2>&1; then
  echo "Desktop user not found. Pass it as the first argument." >&2
  exit 1
fi
USER_HOME=$(getent passwd "$DESKTOP_USER" | cut -d: -f6)
USER_UID=$(id -u "$DESKTOP_USER")
USER_GROUP=$(id -gn "$DESKTOP_USER")
DISPLAY_NUM=${SHADOW_DISPLAY#:}

echo "== Adding the xpra.org apt repository"
. /etc/os-release
wget -qO /usr/share/keyrings/xpra.asc https://xpra.org/xpra.asc
cat > /etc/apt/sources.list.d/xpra.sources <<EOF
Types: deb
URIs: https://xpra.org
Suites: $VERSION_CODENAME
Components: main
Signed-By: /usr/share/keyrings/xpra.asc
EOF

echo "== Installing xpra server, X11 shadow backend, codecs (openh264) and the HTML5 client"
# --no-install-recommends keeps out cups, ibus, audio and the gstreamer stack.
# gir1.2-gtk-3.0 is needed: the X11 shadow server captures through GTK.
# xpra-client and xpra-client-gtk3 are required although xpra-server does not depend on
# them: in 6.5 the server's mmap code imports xpra.client.gui (shipped in xpra-client-gtk3),
# and without it every client hello fails with "error accepting new connection".
# --mmap=no does not avoid it: the window encoder imports xpra.net.mmap unconditionally.
# The GTK client's own dependencies are already pulled in above. python3-xdg silences
# "cannot load menu data".
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  xpra-server xpra-x11 xpra-codecs xpra-html5 xpra-client xpra-client-gtk3 \
  gir1.2-gtk-3.0 python3-gi-cairo python3-xdg python3-setproctitle openssl
xpra --version

echo "== Masking the packaged xpra system proxy (xpra-server.socket)"
# The package enables a socket-activated proxy server on port 14500, reachable from the
# internet. It takes the port before the shadow server can bind it, and is not needed here.
systemctl disable --now xpra-server.socket xpra-server.service 2>/dev/null || true
systemctl mask xpra-server.socket xpra-server.service

install -d -m 750 -o root -g "$USER_GROUP" "$CONF_DIR"

echo "== TLS certificate"
# Browsers only expose WebCodecs (the H.264 decoder) on https pages.
if [ -n "${SSL_CERT:-}" ] && [ -n "${SSL_KEY:-}" ]; then
  CERT=$SSL_CERT
  KEY=$SSL_KEY
  echo "   using $CERT"
else
  CERT=$CONF_DIR/cert.pem
  KEY=$CONF_DIR/key.pem
  if [ ! -s "$CERT" ] || [ ! -s "$KEY" ]; then
    HOST_IP=$(hostname -I | awk '{print $1}')
    HOST_FQDN=$(hostname -f)
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
      -keyout "$KEY" -out "$CERT" -subj "/CN=$HOST_FQDN" \
      -addext "subjectAltName=IP:$HOST_IP,DNS:$HOST_FQDN" 2>/dev/null
    echo "   self-signed certificate created for $HOST_IP / $HOST_FQDN"
  else
    echo "   keeping existing $CERT"
  fi
  chown root:"$USER_GROUP" "$CERT" "$KEY"
  chmod 640 "$CERT" "$KEY"
fi

echo "== Password"
PASS_FILE=$CONF_DIR/password
# xpra compares the file content as is: no trailing newline.
if [ ! -s "$PASS_FILE" ]; then
  printf '%s' "$(openssl rand -base64 24 | tr -d '/+=\n' | cut -c1-20)" > "$PASS_FILE"
  echo "   new password generated"
else
  echo "   keeping existing password"
fi
chown root:"$USER_GROUP" "$PASS_FILE"
chmod 640 "$PASS_FILE"

echo "== systemd unit xpra-shadow.service"
# Waits for the xrdp X socket and the user's runtime dir instead of failing: xpra keeps
# its session files in XDG_RUNTIME_DIR, which only exists while the user is logged in.
# Restart=always brings the shadow back after an xrdp logout + new login.
# Trimmed to screen, keyboard, pointer and clipboard: audio, printing, file transfer,
# notifications, tray, mDNS and dbus are off.
cat > /etc/systemd/system/xpra-shadow.service <<EOF
[Unit]
Description=xpra shadow of the xrdp desktop $SHADOW_DISPLAY (browser, H.264)
After=network-online.target xrdp.service
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
User=$DESKTOP_USER
Environment=DISPLAY=$SHADOW_DISPLAY
Environment=XAUTHORITY=$USER_HOME/.Xauthority
Environment=XDG_RUNTIME_DIR=/run/user/$USER_UID
ExecStartPre=/bin/sh -c 'until [ -S /tmp/.X11-unix/X$DISPLAY_NUM ] && [ -d /run/user/$USER_UID ]; do sleep 5; done'
TimeoutStartSec=infinity
ExecStart=/usr/bin/xpra shadow $SHADOW_DISPLAY --daemon=no \\
  --bind=none \\
  --bind-ssl=0.0.0.0:$XPRA_PORT,auth=file,filename=$PASS_FILE \\
  --ssl-cert=$CERT --ssl-key=$KEY \\
  --html=on --refresh-rate=$REFRESH_RATE \\
  --clipboard=yes \\
  --speaker=off --microphone=off --pulseaudio=no --webcam=no \\
  --printing=no --file-transfer=off --open-files=off --open-url=no \\
  --notifications=no --system-tray=no --tray=no --splash=no \\
  --mdns=no --dbus-control=no --dbus-launch=no \\
  --ssh-upgrade=no
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable xpra-shadow.service
systemctl restart xpra-shadow.service

if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
  echo "== Opening $XPRA_PORT/tcp in ufw"
  ufw allow "$XPRA_PORT/tcp"
fi

sleep 3
systemctl --no-pager --lines=5 status xpra-shadow.service || true
echo
echo "Done. Open https://$(hostname -I | awk '{print $1}'):$XPRA_PORT/ in Chrome."
echo "Password: $(cat "$PASS_FILE")   (stored in $PASS_FILE)"
echo "Self-signed certificate: accept the browser warning once."
echo "Logs: journalctl -u xpra-shadow -f"
