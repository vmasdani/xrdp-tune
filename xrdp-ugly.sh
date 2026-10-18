#!/bin/bash
# Trade looks for latency: flat dark theme, black wallpaper, plain cursor, quiet panel,
# no notifications. Colour depth stays 32 bpp (GFX needs it).
# Run: sudo ./xrdp-ugly.sh [desktop-user]
# Never restarts xrdp. Desktop parts apply at the next login (Xfce: run while logged out of RDP).
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
as_user() { sudo -u "$DESKTOP_USER" HOME="$USER_HOME" "$@"; }
kw() { as_user kwriteconfig5 "$@"; }
xfset() { as_user python3 -I - "$@" < "$(dirname "$0")/xfconf-set.py"; }
# Desktop: XRDP_DESKTOP from install.sh, else whatever ~/.xsession starts.
XRDP_DESKTOP=${XRDP_DESKTOP:-$(grep -qs startxfce4 "$USER_HOME/.xsession" && echo xfce || echo kde)}

echo "== xrdp.ini: keep new_cursors=true (legacy 1-bit cursors make alpha Breeze shapes vanish)"
[ -e /etc/xrdp/xrdp.ini.pre-ugly ] || cp /etc/xrdp/xrdp.ini /etc/xrdp/xrdp.ini.pre-ugly
sed -i -E 's/^new_cursors=.*/new_cursors=true/' /etc/xrdp/xrdp.ini

echo "== Fonts: antialias on (off looks too rough), full hinting, subpixel rgb"
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

if [ "$XRDP_DESKTOP" = xfce ]; then
  echo "== Flat dark theme (Adwaita-dark), solid black wallpaper, no desktop icons"
  # xfwm4's Default theme takes its colours from the GTK theme, so it goes dark too.
  xfset xsettings /Net/ThemeName string Adwaita-dark /Net/IconThemeName string Adwaita
  xfset xfwm4 /general/theme string Default /general/button_layout string "|HMC"
  # rdp0 is the first xorgxrdp output; xfdesktop keys the backdrop by output name.
  BD=/backdrop/screen0/monitorrdp0/workspace0
  xfset xfdesktop $BD/color-style int 0 $BD/image-style int 0 $BD/rgba1 'double[]' 0,0,0,1 \
    /desktop-icons/style int 0

  echo "== Fonts and cursor: same settings for GTK; plain Adwaita cursor, 24 px"
  xfset xsettings /Xft/Antialias int 1 /Xft/Hinting int 1 /Xft/HintStyle string hintfull \
    /Xft/RGBA string rgb /Gtk/CursorThemeName string Adwaita /Gtk/CursorThemeSize int 24

  echo "== Notifications and sounds off (the panel clock has no seconds by default)"
  xfset xfce4-notifyd /do-not-disturb bool true
  xfset xsettings /Net/EnableEventSounds bool false /Net/EnableInputFeedbackSounds bool false
else
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

  echo "== Fonts: same settings for Qt"
  kw --file kdeglobals --group General --key XftAntialias true
  kw --file kdeglobals --group General --key XftHintStyle hintfull
  kw --file kdeglobals --group General --key XftSubPixel rgb

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
fi

echo
echo "Done. Log in to the desktop again to apply."
echo "Rollback: /etc/xrdp/xrdp.ini.pre-ugly; delete ~/.config/fontconfig/fonts.conf;"
if [ "$XRDP_DESKTOP" = xfce ]; then
  echo "Xfce: Settings > Appearance / Window Manager / Desktop, Do Not Disturb off."
else
  echo "KDE: System Settings > Appearance > Breeze, Do Not Disturb off."
fi
