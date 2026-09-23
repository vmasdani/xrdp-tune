# Split VPN routing

Route **one chosen user's** traffic through an OpenVPN tunnel while the rest of
the machine — most importantly your SSH login — keeps using the normal internet
connection. This gives you a stable VPN exit IP for IP-whitelisted admin panels
without ever risking a lockout, even when your own client IP changes constantly
(mobile data / wifi / dynamic ISP address).

## Why not a full tunnel

A full tunnel (`redirect-gateway`) sends *every* packet through the VPN. On a
remote box that also breaks the SSH session you are connected through, because
the replies try to return via the tunnel. The usual "exception" is to pin your
own client IP back to the real link, but that only works if your client IP is
fixed. If it is not, invert the design instead:

- The machine's **default route stays on the real interface** (for example
  `eth0`). SSH, `apt`, and everything else are untouched. Your changing client
  IP is irrelevant, because SSH never enters the tunnel.
- Only traffic from a dedicated user is marked and pushed into the tunnel. Run
  any admin-panel client as that user and it exits with the VPN's public IP.

## IP privacy — making traffic *actually* leave via the VPN

Bringing the tunnel interface up is **not** enough. Getting a private tunnel
address such as `192.168.255.x` only means the interface exists. Three things
must also be true or your real IP leaks:

1. **Policy routing must send the user's packets into the tunnel.** The mark
   plus routing table do this. If the routing table is empty (for example it was
   created while the tunnel was down), packets silently fall back to the real
   interface and you still show your real IP. Always create the table route
   while the tunnel is up.

2. **Source NAT (masquerade) on the tunnel.** Packets leave carrying the
   machine's real source address unless rewritten. The VPN server drops those.
   The `MASQUERADE` rule rewrites the source to the tunnel address so replies
   come back.

3. **Block IPv6 for the VPN user.** A typical OpenVPN profile carries **IPv4
   only**. If the box has IPv6, a request to any dual-stack host (most of them)
   leaves over IPv6, completely bypassing the tunnel and exposing your real
   address. Reject IPv6 for the VPN user so it is forced onto the IPv4 tunnel.

The public IP a whitelisted panel actually sees is the **VPN server's** public
address, not the `192.168.255.x` tunnel address. Find it and whitelist it with:

```
sudo -u vpnuser curl -s ifconfig.me; echo
```

It must print the VPN server's public IP. If it prints your real IP or an IPv6
address, one of the three points above is missing.

## Files

| file                    | purpose                                              |
|-------------------------|------------------------------------------------------|
| `vpn-split.conf`        | shared settings (interface, user, mark, table)       |
| `vpn-split-up.sh`       | apply the routing rules (non-persistent, run by hand)|
| `vpn-split-down.sh`     | remove the routing rules                             |
| `install-persistent.sh` | patch a `.ovpn` so the rules apply on every connect  |

## One-time setup

Create the dedicated user once:

```
sudo useradd -m vpnuser
```

Then choose who to route in `vpn-split.conf`:

- Leave `VPN_USER=""` (the default) to **auto-detect** the human running the
  command. The scripts use `$SUDO_USER` (the user behind `sudo`) and fall back
  to `$USER`. They refuse to route `root`.
- Or set `VPN_USER` to a fixed name such as `vpnuser` for a dedicated account.

Set `VPN_DEV` to your tunnel interface if it is not `tun0`.

## Non-persistent use (rules gone after reboot or VPN restart)

Start the VPN and, while it is up, apply the rules:

```
sudo openvpn --config /path/to/profile.ovpn        # terminal 1, keep running
sudo ~/xrdp-tune/vpn/vpn-split-up.sh               # terminal 2
sudo -u vpnuser curl -s ifconfig.me; echo          # expect the VPN server IP
```

Remove them again with:

```
sudo ~/xrdp-tune/vpn/vpn-split-down.sh
```

## Keeping the VPN connected

`openvpn` runs in the foreground and stays connected until you stop it with
Ctrl-C. Do **not** wrap it in `timeout` except for a quick test; `timeout 10`
disconnects after ten seconds by design. To keep it running after you log out,
start it detached, for example inside `tmux`/`screen`, or:

```
sudo nohup openvpn --config ~/xrdp-tune/vpn/<name>.split.ovpn >/tmp/ovpn.log 2>&1 &
```

## Persistent use (rules apply automatically on every connect)

Put your `.ovpn` profiles in this directory and run the installer with no
arguments. It patches **every** `*.ovpn` here and writes a patched copy named
`<name>.split.ovpn` beside each one. The originals are left untouched, and each
copy has any `redirect-gateway` line commented out automatically.

```
~/xrdp-tune/vpn/install-persistent.sh              # all *.ovpn in this folder
~/xrdp-tune/vpn/install-persistent.sh a.ovpn b.ovpn # or only these
```

From then on, just run a patched profile as root; the rules install themselves
on connect and are cleaned up on disconnect:

```
sudo openvpn --config ~/xrdp-tune/vpn/<name>.split.ovpn
```

Both the source profiles and the `.split.ovpn` copies are ignored by
`.gitignore`, so real credentials never reach the repository.

## What to comment out or add in the `.ovpn`

The persistent installer adds these lines for you, but if you edit a profile by
hand, this is what matters. Use absolute paths to the scripts.

**Add** (order does not matter):

```
script-security 2                       # allow OpenVPN to run the helper scripts
route-up /absolute/path/to/vpn-split-up.sh
down     /absolute/path/to/vpn-split-down.sh
pull-filter ignore "redirect-gateway"   # refuse a server push that grabs the default route
```

**Comment out** (prefix with `#`) any line that would turn on a full tunnel,
because it fights the split design and can lock out SSH:

```
#redirect-gateway def1
#redirect-gateway def1 bypass-dhcp
```

If a profile still has an **active** `redirect-gateway def1`, comment it out
before using that profile with this split setup.

## Notes

- The `block-outside-dns` warning OpenVPN prints on connect is harmless. It is a
  Windows-only directive that Linux ignores.
- The routing table, `ip rule`, and `iptables` rules are **not** persistent
  across reboot on their own. Use the persistent installer (which re-applies
  them on every VPN connect) rather than trying to save firewall state.
- Only one VPN profile should be active at a time.

## Routing your own login user instead of a dedicated user

You can set `VPN_USER` to your own login name so all of your traffic goes
through the VPN. This is convenient but carries real trade-offs:

- **SSH safety.** The up script adds a safeguard rule that never marks packets
  sent from source port 22, so `sshd` replies always stay on the real link and
  your remote session survives. Do not remove that rule while using this mode.
  If your SSH server listens on a non-standard port, change `--sport 22` in
  `vpn-split-up.sh` (and `vpn-split-down.sh`) to match, or the safeguard will
  not cover it.
- **All your traffic is tunnelled.** `apt`, `git`, browsers, everything you run
  as this user exits via the VPN server. If the VPN drops while the rules are
  active, that traffic blackholes until you run `vpn-split-down.sh`.
- **No IPv6 for you.** The IPv6 REJECT applies to this user, so your own IPv6 is
  disabled while active.

To go back to the safe, isolated design, set `VPN_USER="vpnuser"` in
`vpn-split.conf`, run `vpn-split-down.sh`, then `vpn-split-up.sh` again.

Always test a change with the VPN kill-timer and the down script ready:

```
sudo timeout 120 openvpn --config /path/to/profile.ovpn   # self-kills in 120s
sudo ~/xrdp-tune/vpn/vpn-split-up.sh
curl -s ifconfig.me; echo                                 # expect the VPN server IP
```

If anything goes wrong, the VPN dies on its own after the timeout and normal
routing returns; or run `sudo ~/xrdp-tune/vpn/vpn-split-down.sh`.
