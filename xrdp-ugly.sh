#!/bin/bash
# Trade looks for latency: flat dark theme, black wallpaper, plain cursor, quiet panel,
# no notifications, legacy RDP cursors. Colour depth stays 32 bpp (GFX needs it).
# Run: sudo ./xrdp-ugly.sh [desktop-user]
# Never restarts xrdp. KDE parts apply at next Plasma login; new_cursors after xrdp restart.
# Manual, biggest wins (see README): client resolution 1024x640, Chrome/VS Code flags.
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
kw() { sudo -u "$DESKTOP_USER" HOME="$USER_HOME" kwriteconfig5 "$@"; }

echo "== xrdp.ini: legacy 16-colour cursors (smaller cursor updates)"
cp -n /etc/xrdp/xrdp.ini /etc/xrdp/xrdp.ini.pre-ugly
sed -i -E 's/^new_cursors=.*/new_cursors=false/' /etc/xrdp/xrdp.ini

echo "== Flat dark theme, solid black wallpaper, no icon effects"
kw --file kdeglobals --group General --key ColorScheme BreezeDark
kw --file kdeglobals --group General --key Name "Breeze Dark"
kw --file kdeglobals --group Icons --key Theme breeze-dark
kw --file kdeglobals --group KDE --key widgetStyle Breeze
kw --file kdeglobals --group KDE --key LookAndFeelPackage org.kde.breezedark.desktop
kw --file plasmarc --group Theme --key name breeze-dark
kw --file kwinrc --group org.kde.kdecoration2 --key theme Breeze
kw --file kwinrc --group org.kde.kdecoration2 --key BorderSize None
kw --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft ""
kw --file breezerc --group Common --key ShadowSize ShadowNone
kw --file breezerc --group Windeco --key DrawBackgroundGradient false
kw --file breezerc --group Windeco --key DrawTitleBarSeparator false
kw --file breezerc --group Style --key AnimationsEnabled false
kw --file breezerc --group Style --key MenuOpacity 100
# Solid black wallpaper on every existing desktop containment (the plugin's default is blue).
APPLETS="$USER_HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
if [ -f "$APPLETS" ]; then
  sed -i -E 's/^wallpaperplugin=.*/wallpaperplugin=org.kde.color/' "$APPLETS"
  for c in $(sed -n -E 's/^\[Containments\]\[([0-9]+)\]$/\1/p' "$APPLETS"); do
    kw --file plasma-org.kde.plasma.desktop-appletsrc \
      --group Containments --group "$c" --group Wallpaper --group org.kde.color --group General \
      --key Color 0,0,0
  done
fi

echo "== Fonts: antialias on (off looks too rough), full hinting, subpixel rgb"
kw --file kdeglobals --group General --key XftAntialias true
kw --file kdeglobals --group General --key XftHintStyle hintfull
kw --file kdeglobals --group General --key XftSubPixel rgb
FC_DIR="$USER_HOME/.config/fontconfig"
mkdir -p "$FC_DIR"
cat > "$FC_DIR/fonts.conf" <<'XML'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="font"><edit name="antialias" mode="assign"><bool>true</bool></edit></match>
  <match target="font"><edit name="hinting" mode="assign"><bool>true</bool></edit></match>
  <match target="font"><edit name="hintstyle" mode="assign"><const>hintfull</const></edit></match>
  <match target="font"><edit name="rgba" mode="assign"><const>rgb</const></edit></match>
</fontconfig>
XML
chown -R "$DESKTOP_USER:" "$FC_DIR"

echo "== Cursor: plain Breeze, 24 px, no animated theme"
kw --file kcminputrc --group Mouse --key cursorTheme breeze_cursors
kw --file kcminputrc --group Mouse --key cursorSize 24

echo "== Panel: no clock seconds; notifications off"
if [ -f "$APPLETS" ]; then
  sed -i -E 's/^showSeconds=.*/showSeconds=false/' "$APPLETS"
fi
kw --file plasmanotifyrc --group DoNotDisturb --key Until 9999-12-31T23:59:59
kw --file plasmanotifyrc --group Notifications --key PopupTimeout 1000
kw --file knotifyrc --group Sounds --key Use false
kw --file kdeglobals --group Sounds --key Enable false

echo
echo "Done. Re-login to Plasma to apply. new_cursors applies after the next xrdp restart"
echo "(log out of RDP first): sudo systemctl restart xrdp"
echo "Rollback: /etc/xrdp/xrdp.ini.pre-ugly; KDE: System Settings > Appearance > Breeze,"
echo "delete ~/.config/fontconfig/fonts.conf, Do Not Disturb off."
