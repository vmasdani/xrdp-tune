#!/bin/bash
# Flameshot screenshots on Ctrl+Alt+Shift+P (region select, Enter copies to the clipboard,
# which xrdp passes to the client). Handy for pasting screenshots into AI chats/agents.
# Run: sudo ./xrdp-flameshot.sh [desktop-user]
# Never restarts xrdp. The shortcut applies at the next desktop login: log out of RDP first,
# because a running kglobalaccel (KDE) or xfconfd (Xfce) rewrites the shortcut file on logout.
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
xfset() { as_user python3 -I - "$@" < "$(dirname "$0")/xfconf-set.py"; }
# Desktop: XRDP_DESKTOP from install.sh, else whatever ~/.xsession starts.
XRDP_DESKTOP=${XRDP_DESKTOP:-$(grep -qs startxfce4 "$USER_HOME/.xsession" && echo xfce || echo kde)}

echo "== Installing flameshot"
DEBIAN_FRONTEND=noninteractive apt-get install -y flameshot

if [ "$XRDP_DESKTOP" = xfce ]; then
  echo "== Ctrl+Alt+Shift+P: flameshot gui (Xfce keyboard shortcut)"
  # Xfce reads /commands/custom only once custom/override is true, and then ignores
  # /commands/default. Start custom from the defaults (Alt+F2, Ctrl+Alt+T, ...) if it is
  # missing, so they keep working next to the new binding.
  xfset xfce4-keyboard-shortcuts --copy /commands/default /commands/custom \
    /commands/custom/override bool true \
    '/commands/custom/<Primary><Shift><Alt>p' string 'flameshot gui'
else
  echo "== Ctrl+Alt+Shift+P: flameshot gui"
  # Same layout Plasma 5.27 writes for System Settings > Shortcuts > Add Command:
  # a hidden .desktop file plus a [<name>.desktop] group in kglobalshortcutsrc.
  APPS="$USER_HOME/.local/share/applications"
  as_user mkdir -p "$APPS"
  as_user tee "$APPS/flameshot.desktop" >/dev/null <<'EOF'
[Desktop Entry]
Exec=flameshot gui
Name=flameshot gui
NoDisplay=true
StartupNotify=false
Type=Application
X-KDE-GlobalAccel-CommandShortcut=true
EOF
  kw() { as_user "$(command -v kwriteconfig6 || echo kwriteconfig5)" --file kglobalshortcutsrc --group flameshot.desktop "$@"; }
  kw --key _k_friendly_name "flameshot gui"
  kw --key _launch "Ctrl+Alt+Shift+P,none,flameshot gui"
fi

echo
echo "Done. Log out of the RDP session and back in, then press Ctrl+Alt+Shift+P."
echo "Drag a region, press Enter (or Ctrl+C) to copy, paste on the client."
if [ "$XRDP_DESKTOP" = xfce ]; then
  echo "Rollback: Settings > Keyboard > Application Shortcuts, remove flameshot gui;"
  echo "  apt-get remove flameshot."
else
  echo "Rollback: delete ~/.local/share/applications/flameshot.desktop and the"
  echo "[flameshot.desktop] group in ~/.config/kglobalshortcutsrc; apt-get remove flameshot."
fi
