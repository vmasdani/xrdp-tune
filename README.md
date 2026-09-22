# xrdp-tune

Fast RDP on a GPU-less budget VPS: Ubuntu 24.04, KDE Plasma 5 (X11), xrdp 0.10 built from
source with the GFX pipeline. Tuned for the Windows App client on Android (RFX Progressive,
no H.264 decode) and Windows mstsc.

## The setup it is built for

A tablet used as a thin laptop: keyboard and touchpad first, touch as a fallback.

- **Client:** Samsung Galaxy Tab S7 running the Windows App, docked on a cheap floating-style
  cantilever ("magic") magnetic keyboard with a built-in touchpad.
- **Server:** a cheap VPS with no GPU. Everything renders in software on the CPU, so every
  pixel and every animation costs latency.
- **Workload:** AI coding and agent orchestration (terminals, editor, browser, many parallel
  agent sessions), or anything else that is mostly text. The desktop stays up on the VPS
  while the tablet disconnects and reconnects.

Choices that follow from this: flat dark theme and no effects (cheap to encode), keyboard
shortcuts for common actions, pointer mode for the touchpad rather than touch mode, clipboard kept (paste
screenshots and logs into AI chats), audio and drive redirection dropped.

![Tablet with a magnetic keyboard, a similar form factor](https://upload.wikimedia.org/wikipedia/commons/thumb/2/2d/Samsung_Galaxy_TabPro_S_%2823850808283%29.jpg/960px-Samsung_Galaxy_TabPro_S_%2823850808283%29.jpg)

<sub>Similar form factor (Galaxy TabPro S). Photo: Maurizio Pesce,
[CC BY 2.0](https://creativecommons.org/licenses/by/2.0/), via
[Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Samsung_Galaxy_TabPro_S_(23850808283).jpg).</sub>

## Fresh install

```
git clone <this repo> xrdp-tune
cd xrdp-tune
sudo ./install.sh            # desktop user = the user who ran sudo
sudo ./install.sh someuser
```

`install.sh` runs the five scripts below with `NO_RESTART=1`, then starts xrdp once.
Takes a while: it builds xrdp and xorgxrdp.

## Scripts

| Script | What it does | Restarts xrdp |
|---|---|---|
| `install.sh` | All of the below, one start at the end | yes |
| `xrdp-ugly.sh` | Looks for latency: Breeze Dark flat theme, solid black wallpaper, no window borders/shadows, fonts antialiased with hintfull, no subpixel, plain 24 px cursor, legacy RDP cursors, no clock seconds, notifications off | never |
| `xrdp-setup.sh` | Plasma + apps, xrdp 0.10.6.1 + xorgxrdp 0.10.5 from source, GFX (32 bpp), 4 MB TCP buffers, H.264 bitrate cap, startwm.sh, `.xsession`, KDE compositing/animations off | yes, unless `NO_RESTART=1` |
| `xrdp-snappy.sh` | BBR, `tcp_notsent_lowat`, no slow start after idle, 60 fps frame interval | yes, unless `NO_RESTART=1` |
| `xrdp-lean.sh` | Channels down to clipboard + drdynvc, xrdp nice -10 / Xorg -5 / desktop 0, fq qdisc, AES-128-GCM first, LogLevel WARNING, no DPMS, 512 KB send buffer (experimental), 8 ms frame interval (experimental), remaining KDE effects and shadows off | never |
| `xrdp-flameshot.sh` | Installs Flameshot, binds Ctrl+Alt+Shift+P to `flameshot gui` (region select, Enter copies to the clipboard, which reaches the client). Applies at the next Plasma login | never |

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

## Client (Windows App on Android, tablet + keyboard + touchpad)

- Custom resolution 1280x800, scale 100%. Smaller resolution = biggest bandwidth win.
- Redirection: sound, storage, camera, microphone off. Clipboard on.
- Mouse mode "Mouse pointer", not touch. The keyboard's touchpad then drives a real pointer
  with exact clicks and hover; screen taps still work as clicks.
- Physical keyboard: Ctrl/Alt/Shift shortcuts reach the session (e.g. Ctrl+Alt+Shift+P for
  Flameshot). Combos that Android or One UI grab first never arrive; pick bindings around them.
- 5 GHz Wi-Fi. Colour depth must stay 32 bpp or GFX turns off.

## Screenshots

`xrdp-flameshot.sh` binds **Ctrl+Alt+Shift+P** to `flameshot gui`. Drag a region, press Enter
(or Ctrl+C) to copy, then paste on the tablet or straight into an AI chat in the session.
The shortcut is stored as a Plasma "custom command" (`~/.local/share/applications/flameshot.desktop`
plus a `[flameshot.desktop]` group in `~/.config/kglobalshortcutsrc`). Run the script while
logged out of RDP; a running session rewrites that file on logout.

## Notes

`xrdp-notes` holds the full history: what each change does, why, and how to roll it back.
`xrdp.ini.bak` is the original distro 0.9 config.
