#!/bin/bash
# Flameshot screenshots on Ctrl+Alt+Shift+P (region select, Enter copies to the clipboard,
# which xrdp passes to the client). Handy for pasting screenshots into AI chats/agents.
# Run: sudo ./xrdp-flameshot.sh [desktop-user]
# Never restarts xrdp. The shortcut applies at the next Plasma login: log out of RDP first,
# because a running kglobalaccel rewrites kglobalshortcutsrc on logout.
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

echo "== Installing flameshot"
DEBIAN_FRONTEND=noninteractive apt-get install -y flameshot

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
kw() { as_user kwriteconfig5 --file kglobalshortcutsrc --group flameshot.desktop "$@"; }
kw --key _k_friendly_name "flameshot gui"
kw --key _launch "Ctrl+Alt+Shift+P,none,flameshot gui"

echo
echo "Done. Log out of the RDP session and back in, then press Ctrl+Alt+Shift+P."
echo "Drag a region, press Enter (or Ctrl+C) to copy, paste on the client."
echo "Rollback: delete ~/.local/share/applications/flameshot.desktop and the"
echo "[flameshot.desktop] group in ~/.config/kglobalshortcutsrc; apt-get remove flameshot."
