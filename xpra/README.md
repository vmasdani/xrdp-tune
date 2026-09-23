# Browser access over H.264 (xpra shadow)

A second way into the same desktop: a browser tab instead of an RDP client. The xpra shadow
server mirrors the running xrdp X display and streams it to xpra's HTML5 client. Chrome on
Android decodes H.264 in hardware through WebCodecs, which the Windows App on Android does
not do for RDP. xrdp keeps working next to it; both can be connected at the same time.

## Verdict: not worth it

Tried on the target setup (GPU-less VPS, Galaxy Tab S7, Chrome): **xpra is laggier than
xrdp with RFX Progressive.** Stay on xrdp. This folder is kept as a record, not a
recommendation.

Why it loses on this box:

- **Polling, not damage.** The X11 shadow backend gets no damage events from the xrdp X
  server. It grabs the whole screen every refresh tick and diffs it in software, so a
  keystroke waits for the next poll and every poll costs CPU. xrdp's xorgxrdp driver sees
  each damaged rectangle as it is drawn and encodes only those tiles.
- **Software H.264 on a shared vCPU.** Without a GPU, openh264 encodes on the same CPU that
  runs Plasma, the editor and the agents. RFX tiles are cheaper to encode than H.264 frames.
- **Python in the hot path.** Capture, diffing and packet handling run in the xpra Python
  server; xrdp is C end to end.
- **Browser in the input path.** Keys and pointer go through JavaScript and a websocket; the
  browser also eats some shortcuts before the page sees them.

Setup cost on top of that: xpra 6.5.3's server needs the GTK client package
(`xpra-client-gtk3`) or every connection fails with "error accepting new connection",
`--mmap=no` does not work around it, and the packaged `xpra-server.socket` holds port 14500.
The script handles all three.

H.264 in the browser only pays off with a GPU encoder (NVENC, VA-API) or a capture path
with damage tracking. Neither exists here.

## Install

```
sudo ./xpra-shadow.sh            # desktop user = the user who ran sudo
sudo ./xpra-shadow.sh someuser
REFRESH_RATE=20 sudo -E ./xpra-shadow.sh   # lower CPU
```

Then open `https://<server-ip>:14500/` in Chrome, accept the self-signed certificate warning
once, and enter the password the script printed (stored in `/etc/xpra/shadow/password`).

The script adds the xpra.org apt repository (Ubuntu's own `xpra` package is 3.1, too old),
installs the server, X11 shadow backend, codecs and HTML5 client without recommends,
masks the packaged system proxy (`xpra-server.socket`, which would hold port 14500), creates a self-signed certificate and a random password, and installs
`xpra-shadow.service`. Re-running keeps the certificate and password. It never restarts xrdp.

| Variable | Default | Meaning |
|---|---|---|
| `SHADOW_DISPLAY` | `:10` | X display of the xrdp session (`ls /tmp/.X11-unix`) |
| `XPRA_PORT` | `14500` | HTTPS / secure websocket port |
| `REFRESH_RATE` | `30` | screen polls per second |
| `SSL_CERT`, `SSL_KEY` | self-signed | paths to a real certificate and key |

## How it behaves

- **A session must exist.** The shadow mirrors the xrdp session's X display. Log in over RDP
  once after boot; the unit waits for the display and starts by itself. It also comes back
  after an RDP logout and a new login.
- **Resolution follows the RDP session.** The xrdp client sets the X screen size; the browser
  scales it. Set the resolution you want in the RDP client before disconnecting it.
- **CPU.** Without a GPU, the X11 shadow backend has no damage events. It captures the whole
  screen `REFRESH_RATE` times a second and the encoder works out what changed. Cost grows
  with resolution and refresh rate. Watch `top` while scrolling and lower `REFRESH_RATE` if
  xpra takes too much.
- **Text sharpness.** H.264 in the browser is 4:2:0, so coloured text blurs. xpra switches
  to lossless or WebP for regions that stop changing, so static text sharpens after a moment.
- **HTTPS is required.** Browsers only expose the WebCodecs H.264 decoder on secure pages.
  With a certificate warning clicked through, check the xpra connection info in the HTML5
  client's menu to confirm `h264` is in use. If it falls back to JPEG or WebP only, use a
  real certificate (`SSL_CERT` / `SSL_KEY`).
- **Keyboard.** The browser grabs some shortcuts (Ctrl+W, Ctrl+T, Alt+Tab) before the page
  sees them. Fullscreen mode or installing the page as an app lets more of them through.
- **Trimmed.** Only screen, keyboard, pointer and clipboard. Audio, printing, file transfer,
  notifications, tray, mDNS and dbus are off.

## Checks

```
systemctl status xpra-shadow
journalctl -u xpra-shadow -f
ss -ltnp | grep 14500
top -p "$(pgrep -d, -f 'xpra shadow')"
```

## Rollback

```
sudo systemctl disable --now xpra-shadow
sudo rm /etc/systemd/system/xpra-shadow.service && sudo systemctl daemon-reload
sudo systemctl unmask xpra-server.socket xpra-server.service
sudo apt-get remove xpra-server xpra-x11 xpra-codecs xpra-html5 xpra-client xpra-client-gtk3
sudo rm -r /etc/xpra/shadow /etc/apt/sources.list.d/xpra.sources /usr/share/keyrings/xpra.asc
sudo ufw delete allow 14500/tcp    # only if ufw is active
```
