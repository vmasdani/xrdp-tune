#!/bin/bash
# fail2ban for SSH: bans IPs that keep failing or probing sshd.
# Run: sudo ./xrdp-fail2ban.sh
#      sudo F2B_IGNOREIP="203.0.113.7" ./xrdp-fail2ban.sh   (never ban these, space separated)
#
# 5 failures in 10 min = 1 h ban, doubling for repeat offenders up to 1 week. Bans go through
# ufw when it is active, else fail2ban's default (nftables). Not needed behind a Cloudflare
# Tunnel with port 22 closed. Do not put a VPN exit IP (NordVPN etc.) in F2B_IGNOREIP: it is
# shared with strangers and changes on reconnect.
# Never restarts xrdp. Rollback: sudo rm /etc/fail2ban/jail.d/xrdp-tune.local;
# sudo systemctl disable --now fail2ban (or apt purge fail2ban)
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

echo "== SSH login check"
# Key-only login is the real protection; fail2ban only slows down guessing.
SSHD_T=$(sshd -T 2>/dev/null || true)
if [ -z "$SSHD_T" ]; then
  echo "   WARNING: could not read the sshd config (sshd -T failed). Check key-only login by hand."
elif echo "$SSHD_T" | grep -qiE '^(passwordauthentication|kbdinteractiveauthentication) yes'; then
  echo "   WARNING: SSH password login is ON. Key-only login is mandatory on a public VPS."
  echo "   See ssh-keys-only.md, then rerun this check: sudo sshd -T | grep -i authentication"
else
  echo "   Key-only login: ok"
fi
SSH_PORTS=$(echo "$SSHD_T" | awk '$1 == "port" {print $2}' | paste -sd, -)
SSH_PORTS=${SSH_PORTS:-ssh}

echo "== Installing fail2ban"
# python3-systemd: the systemd backend reads sshd from the journal (no auth.log needed).
apt-get install -y fail2ban python3-systemd

BANACTION=
if ufw status 2>/dev/null | grep -q '^Status: active'; then
  BANACTION="banaction = ufw"
fi

echo "== /etc/fail2ban/jail.d/xrdp-tune.local (ssh port $SSH_PORTS)"
# A drop-in, so an existing jail.local is left alone. .local files are read after .conf.
cat > /etc/fail2ban/jail.d/xrdp-tune.local <<EOF
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 ${F2B_IGNOREIP:-}
backend = systemd
$BANACTION
bantime = 1h
findtime = 10m
maxretry = 5
bantime.increment = true
bantime.maxtime = 1w

[sshd]
enabled = true
port = $SSH_PORTS
# aggressive also catches key-only probes and preauth disconnects
mode = aggressive
EOF

systemctl enable fail2ban
systemctl restart fail2ban
sleep 2
fail2ban-client status sshd
echo "   Unban: sudo fail2ban-client set sshd unbanip <ip>"
