#!/data/data/com.termux/files/usr/bin/bash
# Termux (Android): RDP over SSH tunnel to the VPS, reconnects by itself when it drops.
# Run on the phone, not the VPS: ./termux-rdp-tunnel.sh, then point Windows App at
# 127.0.0.1:3388. Stop with Ctrl+C.
# Settings: edit the defaults below, or pass them in, e.g.
#   HOST=ssh.example.com SSH_USER=me KEY=~/ssh_priv ./termux-rdp-tunnel.sh
# CF=1 (default) goes through Cloudflare Tunnel (needs `pkg install cloudflared`),
# CF=0 is direct SSH to the VPS (port 22 open).
set -u

HOST=${HOST:-ssh.example.com}
SSH_USER=${SSH_USER:-username}
KEY=${KEY:-$HOME/.ssh/id_ed25519}
LOCAL_PORT=${LOCAL_PORT:-3388}
CF=${CF:-1}

opts=(
  -i "$KEY" -N -L "$LOCAL_PORT:127.0.0.1:3389"
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

# xrdp keeps the session, so the RDP client reconnects to the same desktop.
while true; do
  ssh "${opts[@]}" "$SSH_USER@$HOST"
  rc=$?
  echo "$(date +%T) tunnel closed (exit $rc), reconnecting in 2 s. Ctrl+C to stop."
  sleep 2
done
