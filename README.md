# xrdp-tune

Fast RDP on a GPU-less budget VPS: Ubuntu 24.04 or 26.04, KDE Plasma or Xfce (X11), xrdp 0.10
with the GFX pipeline (Ubuntu package on 26.04, built from source on 24.04). Tuned for the Windows App client on Android (RFX Progressive,
no H.264 decode) and Windows mstsc.

## Why this exists

Efficiency while maintaining effectiveness.

A decent laptop today, 12 to 16 GB of RAM, costs about $1000 (IDR 17 million). A VPS that runs
this whole desktop costs about $10 a month (IDR 150k). Ten dollars a month is eight years of
rent before it matches the laptop's price tag, and by then the laptop has been replaced once,
probably twice.

It is the Grab/Uber versus owning-a-car argument. Owning the car feels better: it is yours, it
is always in the driveway, nobody else touched it. But you paid for it up front, you pay for
it while it sits idle, you pay when it breaks, and when it dies it takes everything in the
boot with it. Renting the ride means paying only for the trips you take, swapping the vehicle
the moment it stops working, and never once caring about the engine. For a developer, the
"trips" are terminals, an editor, a browser and a pile of coding agents. None of that needs
the car. It needs a good enough seat and a window.

The trade is real: there is network lag, and no internet means no work. The point of this repo
is to make the lag small enough that you stop noticing it, so the cheap option stays the
effective option. Every script here is one step of that.

Besides, it is cool. A $200 tablet on your lap, a whole Linux workstation behind it, and the
same desktop waiting for you on any screen you pick up next.

Longer version: [The $10/Month Dev Machine](https://vmasdani.my.id/blog/ten-dollar-dev-machine).

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

## Recommended providers

Not an endorsement, and no affiliate links. These are budget providers that sell KVM VPS
plans big enough for this desktop. Prices were checked in October 2026, are the cheapest
advertised rate (often tied to a long term or an intro period), and change often: confirm on
the provider's site before you buy.

| Provider | Type | RAM | Processor | Price / mo |
|---|---|---|---|---|
| [Contabo](https://contabo.com/en/vps/) | Cloud VPS 4 (KVM) | 8 GB | 4 vCPU | €4.40 (24-month term), €5.50 monthly |
| [OVHcloud](https://us.ovhcloud.com/vps/) | VPS-1 (KVM) | 4 GB | 2 vCore | from $4.54 |
| [OVHcloud](https://us.ovhcloud.com/vps/) | VPS-2 (KVM) | 8 GB | 4 vCore | from $8.50 |
| [Hostinger](https://www.hostinger.com/vps-hosting) | KVM 2 | 8 GB | 2 vCPU, AMD EPYC | $8.99 intro, $14.99 renewal |
| [InterServer](https://www.interserver.net/vps/) | Linux VPS, 4 slices (KVM) | 8 GB | 4 cores | about $24 ($6 per slice of 1 core / 2 GB) |
| [SumoPod](https://sumopod.com/) | VPS (Tencent Cloud or Cloudeka), Jakarta or Singapore | 4 GB | 2 vCPU | about Rp 85k |
| [SumoPod](https://sumopod.com/) | VPS (Tencent Cloud or Cloudeka), Jakarta or Singapore | 8 GB | 2 vCPU | about Rp 150k |

**8 GB of RAM is plenty.** Linux with zram (`xrdp-zram.sh`, which `install.sh` offers)
compresses swapped-out pages in RAM with zstd, typically at 2:1 to 3:1 for desktop and
browser memory. An 8 GB box then holds Plasma, Brave, an editor and several coding agents
without touching the disk. 4 GB works for a lighter load.

Pick the region closest to you: round-trip time matters more than core count for how the
desktop feels. Cheap plans share CPUs, so run `./cpu-steal-check.sh` on a new box. If the
host takes a large share of the vCPU (long stalls, a high "taken by the host" percentage),
ask for a migration or move providers.

## Fresh install

```
git clone <this repo> xrdp-tune
cd xrdp-tune
sudo ./install.sh            # asks, desktop user defaults to the user who ran sudo
sudo ./install.sh someuser
sudo ./install.sh -y         # every default, no questions
```

`install.sh` asks what to install (desktop: KDE Plasma or Xfce, each tuning script, zram size
and compressor, disk swapfile size), with recommended sizes worked out from the machine's RAM: zram = RAM
(max 16 GB), swapfile = RAM / 2 (2 to 8 GB). Many VPS images already come with a swap; it is
detected and kept, and the installer offers an extra swapfile next to it (recommended only
when the existing one is below RAM / 2). It shows a review and starts only after `y`.
The chosen scripts run with `NO_RESTART=1`, swap first, then xrdp starts once.
On 24.04 it takes a while: Ubuntu only packages xrdp 0.9 there, so it builds xrdp and
xorgxrdp 0.10. On 26.04 it installs Ubuntu's xrdp 0.10.1 and xorgxrdp 0.10.2 with apt. That
build has no x264, so every client gets RFX; set `XRDP_BUILD=1` to build from source anyway
(newer xrdp, H.264 for clients such as Windows mstsc).

## KDE Plasma or Xfce

KDE Plasma is the default. Xfce is the lighter option: its core uses about 250 to 350 MB less
memory than Plasma's (about 470 MB PSS measured on the 11 GB box). Both get compositing and
animations off, so menus, popups and typing feel about the same: a keypress goes from xrdp
to Xorg to the app and never touches the window manager.

The one real latency gain is window drag. `xrdp-lean.sh` turns on xfwm4's wireframe move and
resize (`box_move`, `box_resize`): a drag only changes a thin outline per frame, then the
window redraws once on release. A live drag repaints the window and everything it uncovers on
every frame, which is the heaviest load RDP gets without a GPU.

What Xfce gives up: KRunner, Klipper's history (xfce4-clipman is simpler), Plasma's window
rules and shortcut editor. It is installed with `--no-install-recommends`, because the
recommends pull in lightdm, cups, pulseaudio, gnome-keyring, ibus and screen lockers.
Without gnome-keyring, Brave keeps cookies in its basic store (fixed key, not the OS keyring);
fine for a single-user VPS with a password manager such as Bitwarden.

The other scripts read the desktop from `~/.xsession` (`startxfce4` means Xfce), or from
`XRDP_DESKTOP=kde|xfce`, which `install.sh` passes on. Xfce settings are written straight into
`~/.config/xfce4/xfconf/` by `xfconf-set.py`, since `xfconf-query` needs a running session;
run the scripts while logged out of RDP, or they stop with a message.

**Switching an existing box:** Brave chooses its cookie and password encryption from the
desktop (kwallet under KDE, libsecret or basic under Xfce). Moving a profile across desktops
logs you out of every site. Start Brave with `--password-store=kwallet5` in both to keep it.
Step-by-step switch of an existing KDE box, without rebuilding xrdp:
[xfce-switch.md](xfce-switch.md).

## Security: RDP over SSH

> **Warning:** do not expose xrdp directly to the internet on a public VPS. Port 3389 open to
> the world gets scanned and brute-forced constantly. Tunnel RDP over SSH instead, which is
> more secure: block 3389 in the VPS firewall or provider security group and keep only SSH
> (22) open. `install.sh` prints the same warning when it finishes.

Windows App on Android, through Termux:

1. Install [Termux](https://f-droid.org/packages/com.termux/), then `pkg install openssh`.
2. Save the tunnel as `~/rdp.sh` in Termux and make it executable (`chmod +x ~/rdp.sh`):

   ```
   ssh -N -L 3389:127.0.0.1:3389 username@host
   ```

3. Run `./rdp.sh` and leave Termux open in the background.
4. In the Windows App, add a PC at `127.0.0.1:3389` (not the VPS address). The connection
   goes through the SSH tunnel to xrdp on the VPS.

SSH key login (`ssh-keygen` in Termux, `ssh-copy-id username@host`) avoids typing the
password on every connect. To turn off SSH password login entirely, with the key kept in
Bitwarden, see [ssh-keys-only.md](ssh-keys-only.md).

## Scripts

| Script | What it does | Restarts xrdp |
|---|---|---|
| `install.sh` | Asks, reviews, then runs the chosen scripts below, one start at the end | yes |
| `xrdp-ugly.sh` | Looks for latency: Breeze Dark (KDE) or Adwaita-dark (Xfce) flat theme, solid black wallpaper, no window borders/shadows, fonts antialiased with hintfull and subpixel rgb, plain 24 px cursor, no clock seconds, notifications off | never |
| `xrdp-setup.sh` | Plasma or Xfce (`XRDP_DESKTOP=xfce`) + apps, xrdp 0.10 from apt (26.04+) or xrdp 0.10.6.1 + xorgxrdp 0.10.5 from source (24.04, or `XRDP_BUILD=1`), GFX (32 bpp), 4 MB TCP buffers, H.264 bitrate cap, startwm.sh, `.xsession`, compositing/animations off | yes, unless `NO_RESTART=1` |
| `xrdp-snappy.sh` | BBR, `tcp_notsent_lowat`, no slow start after idle, 60 fps frame interval | yes, unless `NO_RESTART=1` |
| `xrdp-lean.sh` | Channels down to clipboard + drdynvc, xrdp nice -10 / Xorg -5 / desktop 0, fq qdisc, AES-128-GCM first, LogLevel WARNING, no DPMS, 512 KB send buffer (experimental), 8 ms frame interval (experimental), remaining KDE effects and shadows off, or on Xfce wireframe window move/resize, no cursor blink, screen lockers hidden | never |
| `xrdp-flameshot.sh` | Installs Flameshot, binds Ctrl+Alt+Shift+P to `flameshot gui` (region select, Enter copies to the clipboard, which reaches the client). Applies at the next desktop login | never |
| `xrdp-brave.sh` | Brave from Brave's apt repo. Policies: hardware acceleration off, memory saver, no background mode, autoplay and site notifications off, Rewards/VPN/Tor/News/Talk/Leo/Playlist and telemetry off. Launcher flags: smooth scrolling off, reduced motion. Applies at the next Brave start | never |
| `xrdp-litexl.sh` | Lite XL 2.1.8 (official portable addons build, SHA-256 pinned) in `~/.local/lite-xl`, menu entry, `lite-xl` on the PATH. A plugin turns off animations and cursor blink. See [Editor](#editor-lite-xl) | never |
| `xrdp-zram.sh` | Compressed swap in RAM: zram0 (zstd, size = RAM, priority 100) via systemd-zram-generator, disk swapfile kept as overflow, zswap off, swappiness 180, page-cluster 0. Starts live, no reboot | never |
| `xfconf-set.py` | Helper for the Xfce branches: sets xfconf properties by editing the channel XML, no session needed | - |
| `xrdp-swapfile.sh` | Disk swapfile, default RAM / 2 (2 to 8 GB), overflow behind zram. Skips if a disk swap already exists, unless `--add` (extra file: `/swapfile2`, `/swapfile3`, ...); never resizes or removes one | never |
| `rust-tools/rust-tools.sh` | ripgrep, fd, bat, zoxide (apt) plus Starship and Zellij (latest release), zoxide and Starship hooks in `~/.bashrc`. Not part of `install.sh`; see [rust-tools/README.md](rust-tools/README.md) | never |

Each script can run on its own on an existing box. All are idempotent and back up the files
they edit (`*.pre-snappy`, `*.pre-lean`, `*.pre-ugly`, `/root/xrdp-etc-backup-<timestamp>`).

## After a manual restart

Restarting xrdp also restarts xrdp-sesman. Running X sessions become orphaned and a
reconnect starts a second desktop session that hangs on a black screen. **Log out of RDP
before any restart.** Cleanup if it happens: `pgrep -a Xorg`, kill it, reconnect.

```
sudo systemctl daemon-reload && sudo systemctl restart xrdp
```

## Checks

```
ps -o pid,ni,comm -C xrdp,Xorg,xrdp-chansrv,plasmashell   # nice -10 / -5 / -5 / 0 (Xfce: xfwm4)
tc qdisc show dev eth0 | head -1                            # fq
sysctl net.ipv4.tcp_congestion_control                      # bbr
sudo grep -aiE 'gfx|rfx|h\.?264|codec' /var/log/xrdp.log | tail   # needs LogLevel=INFO
```

## Manual latency sacrifices (not scriptable)

- Client resolution 1024x640 instead of 1280x800: ~36% fewer pixels per frame. Biggest lever.
- Chrome: `chrome://flags` smooth scrolling off, reduce motion on, force dark mode on.
  `xrdp-brave.sh` turns smooth scrolling off and reduced motion on for Brave, plus policies.
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
On KDE the shortcut is stored as a Plasma "custom command" (`~/.local/share/applications/flameshot.desktop`
plus a `[flameshot.desktop]` group in `~/.config/kglobalshortcutsrc`). On Xfce it is an
application shortcut in `xfce4-keyboard-shortcuts.xml`, next to the default ones. Run the
script while logged out of RDP; a running session rewrites that file on logout.

## Editor: Lite XL

`xrdp-litexl.sh` installs Lite XL, a VS Code-like editor without Electron: file tree
(Ctrl+\\), Ctrl+P to open a file, Ctrl+Shift+P for commands, Ctrl+Shift+F to search the
project, a dark theme, and syntax highlighting for 100+ languages from the addons build. It
renders in software and redraws only the regions that change, so it is cheap over RDP. Zed
and Lapce need a GPU (on this box they redraw every frame on the CPU), and VSCodium is the
same Electron app as VS Code.

The script's settings live in `~/.config/lite-xl/plugins/xrdp_tune.lua` (no animations, no
cursor blink), so `~/.config/lite-xl/init.lua` stays yours. Put
`config.plugins.xrdp_tune = false` there to drop them. Change the theme with Ctrl+Shift+P,
"ui: settings", Colors.

## Browser access (H.264)

`xpra/xpra-shadow.sh` mirrors the running xrdp desktop to a browser tab over H.264 with
xpra's HTML5 client, next to xrdp. **Tried and not worth it:** noticeably laggier than xrdp
RFX on a GPU-less VPS. Kept as a record; reasons in [xpra/README.md](xpra/README.md).

## Rust CLI tools

`rust-tools/rust-tools.sh` installs ripgrep, fd, bat, zoxide, Starship and Zellij for the
terminal side of the workload. [rust-tools/README.md](rust-tools/README.md) covers usage,
latency notes for RDP, and how to tell coding agents (Claude Code, Codex, Gemini CLI) to
prefer these tools whenever they are installed.

## Old laptop on Windows

[laptop-windows/](laptop-windows/README.md) holds a lean tuning script for Windows 10/11 on an
old gaming laptop (Intel graphics plus a Fermi GeForce 820M), with WSL 2 for Linux. It
explains why Windows beats Linux on that hardware (no Fermi driver or Vulkan on Linux, so
no Counter-Strike 2) and why memory compression stays on.

## Notes

`xrdp-notes` holds the full history: what each change does, why, and how to roll it back.
`xrdp.ini.bak` is the original distro 0.9 config.
