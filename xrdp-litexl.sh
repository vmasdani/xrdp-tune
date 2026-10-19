#!/bin/bash
# Lite XL: a small editor that works like a stripped-down VS Code (file tree, Ctrl+P open
# file, Ctrl+Shift+P command palette, Ctrl+Shift+F search in the project, dark theme), at a
# fraction of the memory. It renders in software and redraws only the regions that changed,
# which suits a GPU-less desktop over RDP. Zed and Lapce need a GPU; VS Code is Electron.
# Run: sudo ./xrdp-litexl.sh [desktop-user]
# Never restarts xrdp. Installs the official portable "addons" build (100+ languages plus
# plugins such as project search and autocomplete) into ~/.local/lite-xl for that user.
set -euo pipefail

LITEXL_VER=v2.1.8
LITEXL_SHA256=64b8ddf77cb8762c3a274b37db98f3af0859d64cbab86ab47dc9ddbcb2a8cf04
LITEXL_TAR="lite-xl-$LITEXL_VER-addons-linux-x86_64-portable.tar.gz"

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

echo "== Downloading Lite XL $LITEXL_VER"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/$LITEXL_TAR" \
  "https://github.com/lite-xl/lite-xl/releases/download/$LITEXL_VER/$LITEXL_TAR"
echo "$LITEXL_SHA256  $TMP/$LITEXL_TAR" | sha256sum -c --quiet

echo "== Installing into $USER_HOME/.local/lite-xl"
# Unpack next to the old copy, then swap, so a failed run leaves the old one working.
# The user's settings live in ~/.config/lite-xl and are never touched here.
as_user mkdir -p "$USER_HOME/.local/bin"
as_user rm -rf "$USER_HOME/.local/lite-xl.new"
as_user mkdir "$USER_HOME/.local/lite-xl.new"
as_user tar -xzf - -C "$USER_HOME/.local/lite-xl.new" --strip-components=1 < "$TMP/$LITEXL_TAR"
as_user rm -rf "$USER_HOME/.local/lite-xl"
as_user mv "$USER_HOME/.local/lite-xl.new" "$USER_HOME/.local/lite-xl"
as_user ln -sfn "$USER_HOME/.local/lite-xl/lite-xl" "$USER_HOME/.local/bin/lite-xl"

echo "== Menu entry"
APPS="$USER_HOME/.local/share/applications"
as_user mkdir -p "$APPS"
as_user tee "$APPS/lite-xl.desktop" >/dev/null <<EOF
[Desktop Entry]
Type=Application
Name=Lite XL
GenericName=Text Editor
Comment=Lightweight code editor
Exec=$USER_HOME/.local/lite-xl/lite-xl %F
Icon=accessories-text-editor
Terminal=false
StartupWMClass=lite-xl
Categories=Development;TextEditor;
MimeType=text/plain;
EOF
# Plasma launches from its sycoca cache, which only learns new entries when rebuilt.
as_user kbuildsycoca5 >/dev/null 2>&1 || true

echo "== RDP settings: no animations, no cursor blink (each is a stream of redrawn frames)"
# A plugin rather than init.lua, so ~/.config/lite-xl/init.lua stays the user's own.
# To turn these off, put in init.lua:  config.plugins.xrdp_tune = false
PLUGINS="$USER_HOME/.config/lite-xl/plugins"
as_user mkdir -p "$PLUGINS"
as_user tee "$PLUGINS/xrdp_tune.lua" >/dev/null <<'EOF'
-- mod-version:3
-- Written by xrdp-tune (xrdp-litexl.sh); rerunning the script overwrites this file.
local config = require "core.config"

config.transitions = false     -- scrolling, tabs and palettes jump instead of animating
config.disable_blink = true    -- a blinking cursor sends a frame twice a second
EOF

echo
echo "Done. Start Lite XL from the menu, or run: lite-xl <folder>"
echo "  Ctrl+P open file, Ctrl+Shift+P commands, Ctrl+Shift+F search in project,"
echo "  Ctrl+\\ toggle the file tree. Themes: Ctrl+Shift+P, 'ui: settings', Colors."
echo "Rollback: rm -rf ~/.local/lite-xl ~/.local/bin/lite-xl"
echo "  ~/.local/share/applications/lite-xl.desktop ~/.config/lite-xl/plugins/xrdp_tune.lua"
