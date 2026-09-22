# xrdp-tune

Fast RDP on a GPU-less budget VPS: Ubuntu 24.04, KDE Plasma 5 (X11), xrdp 0.10 built from
source with the GFX pipeline. Tuned for the Windows App client on Android (RFX Progressive,
no H.264 decode) and Windows mstsc.

## Fresh install

```
git clone <this repo> xrdp-tune
cd xrdp-tune
sudo ./install.sh            # desktop user = the user who ran sudo
sudo ./install.sh someuser
```

`install.sh` runs the four scripts below with `NO_RESTART=1`, then starts xrdp once.
Takes a while: it builds xrdp and xorgxrdp.

## Scripts

| Script | What it does | Restarts xrdp |
|---|---|---|
| `install.sh` | All of the below, one start at the end | yes |
| `xrdp-ugly.sh` | Looks for latency: Breeze Dark flat theme, solid wallpaper, no window borders/shadows, 1-bit fonts (no antialias, hintfull), plain 24 px cursor, legacy RDP cursors, no clock seconds, notifications off | never |
| `xrdp-setup.sh` | Plasma + apps, xrdp 0.10.6.1 + xorgxrdp 0.10.5 from source, GFX (32 bpp), 4 MB TCP buffers, H.264 bitrate cap, startwm.sh, `.xsession`, KDE compositing/animations off | yes, unless `NO_RESTART=1` |
| `xrdp-snappy.sh` | BBR, `tcp_notsent_lowat`, no slow start after idle, 60 fps frame interval | yes, unless `NO_RESTART=1` |
| `xrdp-lean.sh` | Channels down to clipboard + drdynvc, xrdp nice -10 / Xorg -5 / desktop 0, fq qdisc, AES-128-GCM first, LogLevel WARNING, no DPMS, 512 KB send buffer (experimental), 8 ms frame interval (experimental), remaining KDE effects and shadows off | never |

Each script can run on its own on an existing box. All are idempotent and back up the files
they edit (`*.pre-snappy`, `*.pre-lean`, `*.pre-ugly`, `/root/xrdp-etc-backup-<timestamp>`).

## After a manual restart

Restarting xrdp also restarts xrdp-sesman. Running X sessions become orphaned and a
reconnect starts a second Plasma session that hangs on a black screen. **Log out of RDP
before any restart.** Cleanup if it happens: `pgrep -a Xorg`, kill it, reconnect.

```
sudo systemctl daemon-reload && sudo systemctl restart xrdp
```

## Checks

```
ps -o pid,ni,comm -C xrdp,Xorg,xrdp-chansrv,plasmashell   # nice -10 / -5 / -5 / 0
tc qdisc show dev eth0 | head -1                            # fq
sysctl net.ipv4.tcp_congestion_control                      # bbr
sudo grep -aiE 'gfx|rfx|h\.?264|codec' /var/log/xrdp.log | tail   # needs LogLevel=INFO
```

## Manual latency sacrifices (not scriptable)

- Client resolution 1024x640 instead of 1280x800: ~36% fewer pixels per frame. Biggest lever.
- Chrome: `chrome://flags` smooth scrolling off, reduce motion on, force dark mode on.
- VS Code: minimap off, cursor blink off, smooth scrolling off, `terminal.integrated.gpuAcceleration` off.
- Colour depth stays 32 bpp: lower depth disables GFX and is slower, not faster.

## Client (Windows App on Android)

- Custom resolution 1280x800, scale 100%. Smaller resolution = biggest bandwidth win.
- Redirection: sound, storage, camera, microphone off. Clipboard on.
- Mouse mode "Mouse pointer", not touch.
- 5 GHz Wi-Fi. Colour depth must stay 32 bpp or GFX turns off.

## Notes

`xrdp-notes` holds the full history: what each change does, why, and how to roll it back.
`xrdp.ini.bak` is the original distro 0.9 config.
