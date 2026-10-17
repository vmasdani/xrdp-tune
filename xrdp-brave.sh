#!/bin/bash
# Brave browser from Brave's apt repo, tuned for a GPU-less VPS behind xrdp.
# Run: sudo ./xrdp-brave.sh [desktop-user]
# Never restarts xrdp. Close Brave first; policies and flags apply at its next start.
#
# Policies (/etc/brave/policies/managed/xrdp-tune.json, every user, see brave://policy):
#   hardware acceleration off   no GPU: skips the llvmpipe GL path, software compositor only
#   memory saver on, balanced   inactive tabs are discarded, RAM goes to the desktop instead
#   background mode off         no Brave processes left running after the last window closes
#   autoplay off, site notifications blocked, no promotions: fewer surprise frames
#   Rewards, Wallet, VPN, Tor, News, Talk, Leo, local AI, Playlist off: no background services
#   P3A, stats ping, Web Discovery off: less background traffic
# Flags (desktop-user's launcher, ~/.local/share/applications/brave-browser.desktop):
#   --disable-smooth-scrolling       one frame per scroll step, not an animated glide
#   --force-prefers-reduced-motion   sites that honour it drop their animations
#   --force-dark-mode, WebContentsForceDark   dark UI and pages, matches xrdp-ugly.sh
# The flags only apply when Brave starts from the menu, taskbar or xdg-open, not when typed
# as `brave-browser` in a terminal.
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

echo "== Installing Brave (apt repo brave-browser-apt-release.s3.brave.com)"
# Same keyring and .sources file as Brave's own Linux install instructions.
DEBIAN_FRONTEND=noninteractive apt-get install -y curl
REPO=https://brave-browser-apt-release.s3.brave.com
curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
  "$REPO/brave-browser-archive-keyring.gpg"
curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources \
  "$REPO/brave-browser.sources"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y brave-browser

echo "== Policies: /etc/brave/policies/managed/xrdp-tune.json"
mkdir -p /etc/brave/policies/managed
cat > /etc/brave/policies/managed/xrdp-tune.json <<'EOF'
{
  "HardwareAccelerationModeEnabled": false,
  "HighEfficiencyModeEnabled": true,
  "MemorySaverModeSavings": 1,
  "BackgroundModeEnabled": false,
  "AutoplayAllowed": false,
  "DefaultNotificationsSetting": 2,
  "PromotionsEnabled": false,
  "BraveRewardsDisabled": true,
  "BraveWalletDisabled": true,
  "BraveVPNDisabled": true,
  "TorDisabled": true,
  "BraveNewsDisabled": true,
  "BraveTalkDisabled": true,
  "BraveAIChatEnabled": false,
  "BraveLocalAIEnabled": false,
  "BravePlaylistEnabled": false,
  "BraveP3AEnabled": false,
  "BraveStatsPingEnabled": false,
  "BraveWebDiscoveryEnabled": false
}
EOF
chmod 644 /etc/brave/policies/managed/xrdp-tune.json

echo "== Flags: launcher override for $DESKTOP_USER"
FLAGS="--disable-smooth-scrolling --force-prefers-reduced-motion --force-dark-mode --enable-features=WebContentsForceDark"
APPS="$USER_HOME/.local/share/applications"
as_user mkdir -p "$APPS"
# A user .desktop file with the same name shadows the system one, taskbar pins included.
# Rerunning starts again from the system file, so the flags never stack.
for f in brave-browser.desktop com.brave.Browser.desktop; do
  [ -f "/usr/share/applications/$f" ] || continue
  sed -E "s|^(Exec=/usr/bin/brave-browser-stable)|\1 $FLAGS|" "/usr/share/applications/$f" \
    | as_user tee "$APPS/$f" >/dev/null
done

echo
brave-browser --version || true
echo "Done. Close Brave if it is running, then start it from the menu."
echo "Check: brave://policy lists the xrdp-tune policies, brave://version shows the flags."
echo "Rollback: rm /etc/brave/policies/managed/xrdp-tune.json"
echo "  ~/.local/share/applications/{brave-browser,com.brave.Browser}.desktop;"
echo "  apt-get remove brave-browser; rm /etc/apt/sources.list.d/brave-browser-release.sources."
