#!/data/data/com.termux/files/usr/bin/bash
# Termux (Android): RDP over SSH tunnel to the VPS, reconnects by itself when it drops.
# Run on the phone, not the VPS: ./termux-rdp-tunnel.sh
# Menu: 1 = connect, 2 = config (edit, or delete/reset). No key within 5 s = connect.
# Settings are asked once and kept in $CONF; the menu prints the path.
# Cloudflare Tunnel mode needs `pkg install cloudflared`.
set -u

CONF=${XDG_CONFIG_HOME:-$HOME/.config}/termux-rdp-tunnel.conf
VARS=(HOST SSH_USER KEY LOCAL_PORT TARGET_PORT CF)

defaults() {
  HOST=""
  SSH_USER=""
  KEY=$HOME/.ssh/id_ed25519
  LOCAL_PORT=3388
  TARGET_PORT=3389
  CF=1
}

load() {
  defaults
  # shellcheck source=/dev/null
  [ -f "$CONF" ] && . "$CONF"
}

show() {
  echo "  hostname:     $HOST"
  echo "  user:         $SSH_USER"
  echo "  key:          $KEY"
  echo "  local port:   $LOCAL_PORT  (Windows App: 127.0.0.1:$LOCAL_PORT)"
  echo "  target port:  $TARGET_PORT  (xrdp on the VPS)"
  echo "  cloudflare:   $CF  (1 = through Cloudflare Tunnel, 0 = direct SSH)"
}

# ask VAR "prompt": Enter keeps the current value.
ask() {
  local ans
  read -r -p "$2 [${!1}]: " ans
  printf -v "$1" '%s' "${ans:-${!1}}"
}

configure() {
  ask HOST "SSH hostname"
  ask SSH_USER "SSH user"
  ask KEY "Private key path"
  KEY=${KEY/#\~/$HOME}
  ask LOCAL_PORT "Local port"
  ask TARGET_PORT "Target port on the VPS"
  ask CF "Through Cloudflare Tunnel? 1 = yes, 0 = direct"
  mkdir -p "$(dirname "$CONF")"
  for v in "${VARS[@]}"; do printf '%s=%q\n' "$v" "${!v}"; done > "$CONF"
  chmod 600 "$CONF"
  echo "Saved to $CONF"
}

config_menu() {
  local c y
  while true; do
    echo
    echo "Config file: $CONF"
    if [ -f "$CONF" ]; then show; else echo "  (not saved yet)"; fi
    echo "1) Edit  2) Delete / reset  3) Back"
    read -r -p "> " c
    case $c in
      1) configure ;;
      2) read -r -p "Delete $CONF? [y/N] " y
         if [ "$y" = y ] || [ "$y" = Y ]; then
           rm -f "$CONF"; load; echo "Deleted, back to defaults."
         fi ;;
      3|"") return ;;
    esac
  done
}

connect() {
  if [ -z "$HOST" ] || [ -z "$SSH_USER" ]; then
    echo "No config yet."
    configure
    if [ -z "$HOST" ] || [ -z "$SSH_USER" ]; then
      echo "Hostname and user are required." >&2
      exit 1
    fi
  fi
  local opts=(
    -i "$KEY" -N -L "$LOCAL_PORT:127.0.0.1:$TARGET_PORT"
    # Keepalive every 15 s: stops the mobile carrier's NAT and the Cloudflare connection from
    # idling out, and a dead link is noticed after 60 s instead of 3 min.
    -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o TCPKeepAlive=yes
    # Local port taken: exit and retry instead of staying up without a tunnel.
    -o ExitOnForwardFailure=yes
  )
  [ "$CF" = 1 ] && opts+=(-o "ProxyCommand=cloudflared access ssh --hostname %h")

  # Android Doze cuts the network of background apps; the wake lock keeps Termux awake.
  # Also set Termux to "Unrestricted" in Android's battery settings.
  termux-wake-lock 2>/dev/null
  trap 'termux-wake-unlock 2>/dev/null; exit' INT TERM

  echo "Tunnel: 127.0.0.1:$LOCAL_PORT -> $HOST:$TARGET_PORT. Ctrl+C to stop."
  # xrdp keeps the session, so the RDP client reconnects to the same desktop.
  while true; do
    ssh "${opts[@]}" "$SSH_USER@$HOST"
    rc=$?
    echo "$(date +%T) tunnel closed (exit $rc), reconnecting in 2 s. Ctrl+C to stop."
    sleep 2
  done
}

load
while true; do
  echo
  echo "Config file: $CONF"
  echo "1) Connect  2) Config"
  choice=1
  for i in 5 4 3 2 1; do
    printf '\rChoose 1 or 2, connecting in %s s... ' "$i"
    if read -r -s -n 1 -t 1 k; then choice=${k:-1}; break; fi
  done
  # Drop an Enter typed after the digit, or it answers the next prompt.
  while read -r -s -n 1 -t 0.1 _; do :; done
  echo
  case $choice in
    1) connect ;;
    2) config_menu ;;
  esac
done
