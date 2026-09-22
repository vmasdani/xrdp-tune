#!/bin/bash
# Fresh Ubuntu 24.04 server: install KDE Plasma (X11) + xrdp 0.10 built from source,
# with the tuning that made RDP smooth on a GPU-less VPS.
#
# Usage: sudo ./xrdp-setup.sh            (desktop user = the user who ran sudo)
#        sudo ./xrdp-setup.sh someuser
#        NO_RESTART=1 sudo -E ./xrdp-setup.sh   (install.sh uses this; restart later)
#
# Result: xrdp 0.10.x + xorgxrdp 0.10.x, GFX pipeline (client negotiates RFX Progressive),
# KDE compositing and animations off, larger TCP buffers.
# Restarting xrdp kills active RDP sessions.
set -euo pipefail

XRDP_VER=v0.10.6.1
XORGXRDP_VER=v0.10.5
SRC=/usr/local/src/xrdp-build
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

echo "== Installing KDE Plasma (minimal, X11) and apps"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  plasma-desktop plasma-workspace kwin-x11 dbus-x11 kde-config-screenlocker maliit-keyboard \
  konsole dolphin kate kde-spectacle \
  pipewire-module-xrdp

echo "== Installing xrdp build dependencies"
apt-get install -y git build-essential autoconf automake libtool pkg-config nasm \
  libssl-dev libpam0g-dev libx11-dev libxfixes-dev libxrandr-dev libxkbfile-dev \
  libjpeg-dev libfuse3-dev libopus-dev libmp3lame-dev libx264-dev libpixman-1-dev \
  xserver-xorg-dev libepoxy-dev libgbm-dev libdrm-dev openssl

# The distro 0.9 packages conflict with the source build.
if dpkg -l xrdp xorgxrdp 2>/dev/null | grep -q '^ii'; then
  echo "== Removing distro xrdp/xorgxrdp packages"
  systemctl stop xrdp xrdp-sesman 2>/dev/null || true
  if [ -d /etc/xrdp ]; then
    BAK=/root/xrdp-etc-backup-$(date +%Y%m%d-%H%M%S)
    cp -a /etc/xrdp "$BAK"
    echo "   /etc/xrdp backed up to $BAK"
  fi
  apt-get remove -y xrdp xorgxrdp
fi

echo "== Fetching sources"
mkdir -p "$SRC"
cd "$SRC"
rm -rf xrdp xorgxrdp
git clone --depth 1 --recursive --branch "$XRDP_VER" https://github.com/neutrinolabs/xrdp.git
git clone --depth 1 --branch "$XORGXRDP_VER" https://github.com/neutrinolabs/xorgxrdp.git

echo "== Building and installing xrdp $XRDP_VER"
cd "$SRC/xrdp"
./bootstrap
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
  --enable-fuse --enable-jpeg --enable-opus --enable-mp3lame \
  --enable-pixman --enable-x264
make -j"$(nproc)"
make install
ldconfig

# xorgxrdp's configure needs xrdp.pc and headers from xrdp >= 0.10.2,
# so it can only be built after the new xrdp is installed.
echo "== Building and installing xorgxrdp $XORGXRDP_VER"
cd "$SRC/xorgxrdp"
./bootstrap
./configure --prefix=/usr --sysconfdir=/etc
make -j"$(nproc)"
make install

echo "== Configuring xrdp"
# TLS certificate, in case make install did not create one.
if [ ! -s /etc/xrdp/cert.pem ] || [ ! -s /etc/xrdp/key.pem ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$(hostname)" \
    -keyout /etc/xrdp/key.pem -out /etc/xrdp/cert.pem
  chmod 600 /etc/xrdp/key.pem /etc/xrdp/cert.pem
fi

# GFX needs 32 bpp (xrdp refuses GFX at 24). Bigger socket buffers help on WAN links.
sed -i -E \
  -e 's/^max_bpp=.*/max_bpp=32/' \
  -e 's/^#?tcp_send_buffer_bytes=.*/tcp_send_buffer_bytes=4194304/' \
  -e 's/^#?tcp_recv_buffer_bytes=.*/tcp_recv_buffer_bytes=4194304/' \
  /etc/xrdp/xrdp.ini

# H.264 bitrate cap for slow links (1.5 Mbps). Applies to clients that negotiate H.264
# (e.g. Windows mstsc with hardware decode). Clients without it fall back to RFX, which has
# no bitrate knob. The codec order stays H264, RFX so each client gets the best it can decode.
# The lan/wan/... sections inherit from default, so the cap covers every connection type.
sed -i -E '/^\[x264\.default\]/,/^\[/{
  s/^vbv_max_bitrate = .*/vbv_max_bitrate = 1_500/
  s/^vbv_buffer_size = .*/vbv_buffer_size = 150/
}' /etc/xrdp/gfx.toml

# Default sesman.ini runs the Xorg wrapper, which Xwrapper.config
# (allowed_users=console) refuses; use the real server like the distro package.
sed -i 's|^param=Xorg$|param=/usr/lib/xorg/Xorg|' /etc/xrdp/sesman.ini

cat > /etc/xrdp/startwm.sh <<'EOF'
#!/bin/sh

if [ -r /etc/profile ]; then
    . /etc/profile
fi

if [ -r ~/.profile ]; then
    . ~/.profile
fi

export XDG_SESSION_DESKTOP=KDE
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_TYPE=x11

exec /etc/X11/Xsession
EOF
chmod 755 /etc/xrdp/startwm.sh

echo "== Raising kernel socket buffer limits"
printf 'net.core.wmem_max=8388608\nnet.core.rmem_max=8388608\n' > /etc/sysctl.d/90-xrdp.conf
sysctl -p /etc/sysctl.d/90-xrdp.conf

echo "== Configuring KDE session for $DESKTOP_USER"
cat > "$USER_HOME/.xsession" <<'EOF'
#!/bin/sh

export XDG_SESSION_DESKTOP=KDE
export XDG_CURRENT_DESKTOP=KDE
export XDG_SESSION_TYPE=x11

exec startplasma-x11
EOF
chown "$DESKTOP_USER:" "$USER_HOME/.xsession"
chmod 755 "$USER_HOME/.xsession"

# Without a GPU, KWin composites in software (llvmpipe): extra CPU and extra redraws over RDP.
as_user() { sudo -u "$DESKTOP_USER" HOME="$USER_HOME" "$@"; }
as_user kwriteconfig5 --file kwinrc --group Compositing --key Enabled false
as_user kwriteconfig5 --file kwinrc --group Compositing --key AnimationSpeed 0
as_user kwriteconfig5 --file kwinrc --group Compositing --key LatencyPolicy Low
as_user kwriteconfig5 --file kdeglobals --group KDE --key AnimationDurationFactor 0

systemctl daemon-reload
systemctl enable xrdp xrdp-sesman
if [ "${NO_RESTART:-0}" = 1 ]; then
  echo "== NO_RESTART=1: xrdp not (re)started"
else
  echo "== Starting services"
  systemctl restart xrdp-sesman xrdp
  sleep 2
  systemctl --no-pager --lines=5 status xrdp xrdp-sesman || true
fi

echo
xrdp --version | head -1
echo
echo "Done. Connect with an RDP client to port 3389 and pick the Xorg session."
echo "If a Plasma session was already running for $DESKTOP_USER, log out and back in"
echo "so the compositing/animation settings apply."
echo "Check the codec after connecting:"
echo "  sudo grep -aiE 'gfx|rfx|h\\.?264|codec' /var/log/xrdp.log | tail -20"
