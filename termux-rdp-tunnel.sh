#!/data/data/com.termux/files/usr/bin/bash
# Termux (Android): RDP over SSH tunnel to the VPS, reconnects by itself when it drops.
# Run on the phone, not the VPS: ./termux-rdp-tunnel.sh
# Menu: 1 = connect, 2 = config (edit, or delete/reset), 3 = Cloudflare Access login.
# No key within 5 s = connect.
# Settings are asked once and kept in $CONF; the menu prints the path.
# Cloudflare Tunnel mode needs `pkg install cloudflared curl`.
# If Cloudflare Access protects the hostname, it logs in once per session (one URL to open)
# before the loop reconnects; with Access off it connects straight away.
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

# Access in front of the hostname answers plain HTTPS with a 302 to the team's login page.
# Network error or Access off: false, so ssh runs as before.
access_on() {
  curl -s -o /dev/null -m 10 -w '%{redirect_url}' "https://$HOST" | grep -q '/cdn-cgi/access/login'
}

# Reuses the cached Access token while it is valid; prints one login URL only when it has expired.
# Without this, every quick reconnect started a new cloudflared with a new URL, which
# replaced the login page still open in the browser.
access_login() {
  [ "$CF" = 1 ] || return 0
  access_on || return 0
  echo "Cloudflare Access is on for $HOST, checking login..."
  cloudflared access login --quiet --auto-close "https://$HOST" >/dev/null
}

# Menu 3: log in to Access without connecting, e.g. before a trip or when the token expired.
# cloudflared has no logout; logging in again deletes the cached app token for this host
# (~/.cloudflared/<host>-<aud>-token) so a fresh one is fetched.
access_menu() {
  local y
  if [ -z "$HOST" ]; then
    echo "No hostname yet, set it in Config first."
    return
  fi
  if ! access_on; then
    echo "Cloudflare Access is off for $HOST (or $HOST is unreachable). No login needed."
    return
  fi
  if cloudflared access token -app="https://$HOST" >/dev/null 2>&1; then
    echo "Access token for $HOST is valid."
    read -r -p "Log in again anyway? [y/N] " y
    [ "$y" = y ] || [ "$y" = Y ] || return
    rm -f "$HOME/.cloudflared/$HOST"-*-token
  else
    echo "No valid Access token for $HOST."
  fi
  echo "Open the URL below and log in."
  if cloudflared access login --quiet --auto-close "https://$HOST" >/dev/null; then
    echo "Logged in. Connect will use this token until it expires."
  else
    echo "Access login failed." >&2
  fi
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
  local delay=2 start rc
  while true; do
    if ! access_login; then
      echo "$(date +%T) Access login failed, retrying in 10 s. Ctrl+C to stop."
      sleep 10
      continue
    fi
    start=$SECONDS
    ssh "${opts[@]}" "$SSH_USER@$HOST"
    rc=$?
    # Exit within 10 s (local port taken, login refused): wait longer each time, up to 60 s,
    # instead of logging in to the VPS every 2 s. A tunnel that ran a while resets to 2 s.
    if [ $((SECONDS - start)) -lt 10 ]; then
      delay=$((delay * 2 > 60 ? 60 : delay * 2))
    else
      delay=2
    fi
    echo "$(date +%T) tunnel closed (exit $rc), reconnecting in $delay s. Ctrl+C to stop."
    sleep "$delay"
  done
}

load
while true; do
  echo
  echo "Config file: $CONF"
  echo "1) Connect  2) Config  3) Access login"
  choice=1
  for i in 5 4 3 2 1; do
    printf '\rChoose 1, 2 or 3, connecting in %s s... ' "$i"
    if read -r -s -n 1 -t 1 k; then choice=${k:-1}; break; fi
  done
  # Drop an Enter typed after the digit, or it answers the next prompt.
  while read -r -s -n 1 -t 0.1 _; do :; done
  echo
  case $choice in
    1) connect ;;
    2) config_menu ;;
    3) access_menu ;;
  esac
done
