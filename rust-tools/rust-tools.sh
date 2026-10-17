#!/bin/bash
# Rust CLI tools for the terminal-heavy workload: ripgrep, fd, bat, zoxide (apt),
# Starship and Zellij (latest GitHub release binaries, not in Ubuntu 24.04 apt).
# Run: sudo ./rust-tools.sh [desktop-user]
# Never restarts xrdp. Idempotent: re-running upgrades Starship and Zellij to the latest
# release and leaves the ~/.bashrc block alone.
# NO_PROMPT=1 skips the Starship prompt hook in ~/.bashrc (binary still installed).
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

case "$(uname -m)" in
  x86_64)  ARCH=x86_64 ;;
  aarch64) ARCH=aarch64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

echo "== ripgrep, fd, bat, zoxide (apt)"
DEBIAN_FRONTEND=noninteractive apt-get install -y ripgrep fd-find bat zoxide curl tar

# Debian/Ubuntu rename two binaries to avoid clashes with older packages
# (fdclone's fd, bacula's bat). Restore the upstream names in /usr/local/bin.
ln -sf /usr/bin/fdfind /usr/local/bin/fd
ln -sf /usr/bin/batcat /usr/local/bin/bat

# Latest musl build of a GitHub release into /usr/local/bin.
# $1 repo, $2 binary name, $3 asset file name.
install_release() {
  local tmp
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/$1/releases/latest/download/$3" -o "$tmp/$3"
  tar -xzf "$tmp/$3" -C "$tmp" "$2"
  install -m 0755 "$tmp/$2" "/usr/local/bin/$2"
  rm -rf "$tmp"
}

echo "== Starship (latest release)"
install_release starship/starship starship "starship-$ARCH-unknown-linux-musl.tar.gz"

echo "== Zellij (latest release)"
install_release zellij-org/zellij zellij "zellij-$ARCH-unknown-linux-musl.tar.gz"

echo "== ~/.bashrc hooks"
BASHRC="$USER_HOME/.bashrc"
MARK="# >>> rust-tools >>>"
if [ -f "$BASHRC" ] && grep -qF "$MARK" "$BASHRC"; then
  echo "   block already present, left as is"
else
  [ -f "$BASHRC" ] && [ ! -f "$BASHRC.pre-rust-tools" ] && cp -p "$BASHRC" "$BASHRC.pre-rust-tools"
  PROMPT_LINE='command -v starship >/dev/null && eval "$(starship init bash)"'
  [ "${NO_PROMPT:-0}" = 1 ] && PROMPT_LINE="# $PROMPT_LINE"
  as_user tee -a "$BASHRC" >/dev/null <<EOF

$MARK
# zoxide adds "z <part-of-path>" and "zi" (interactive); plain cd is unchanged.
command -v zoxide >/dev/null && eval "\$(zoxide init bash)"
$PROMPT_LINE
# <<< rust-tools <<<
EOF
fi

echo
for t in rg fd bat zoxide starship zellij; do
  printf '%-9s %s\n' "$t" "$("$t" --version 2>/dev/null | head -1)"
done
echo
echo "Done. Open a new terminal (or: source ~/.bashrc) for z and the Starship prompt."
echo "Rollback: remove the '# >>> rust-tools >>>' block from ~/.bashrc (backup in"
echo "~/.bashrc.pre-rust-tools); rm /usr/local/bin/{fd,bat,starship,zellij};"
echo "apt-get remove ripgrep fd-find bat zoxide."
