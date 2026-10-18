# Switching an existing KDE box to Xfce

For a box already set up with KDE Plasma by these scripts. No xrdp rebuild and no xrdp
restart: `startwm.sh` and `~/.xsession` are read at each login. For a fresh box, pick Xfce in
`install.sh` instead. Why Xfce at all (wireframe window drag, less memory) is in the README
section "KDE Plasma or Xfce".

Run the commands as the desktop user; `sudo` where shown.

> **Warning:** logging out of RDP ends every program running inside the session, including
> terminals, editors and coding agents started from Konsole. Save that work first, and run
> phase B from an SSH shell, not from inside the RDP session.

## Phase A: prepare, while still in KDE

1. Install Xfce next to Plasma. The KDE session is not affected: Xfce's autostart entries
   (xfsettingsd, clipman, xscreensaver) are all `OnlyShowIn=XFCE`.

   ```
   sudo apt-get install --no-install-recommends xfce4 xfce4-terminal mousepad xfce4-clipman
   ```

   Do not drop `--no-install-recommends`: the recommends pull in lightdm, cups, pulseaudio,
   gnome-keyring, ibus and screen lockers.

2. Keep Brave's logins. Brave picks its cookie and password encryption from the desktop
   (kwallet under KDE, libsecret or a basic store under Xfce), so an existing profile opened
   under Xfce loses every site login. Pin it to kwallet in the launcher:

   ```
   sed -i -E 's|^(Exec=/usr/bin/brave-browser-stable)( --password-store=kwallet5)?|\1 --password-store=kwallet5|' \
     ~/.local/share/applications/brave-browser.desktop
   ```

   The wallet still unlocks at login under Xfce: `/etc/pam.d/xrdp-sesman` has
   `pam_kwallet5.so auto_start`, and its `pam_kwallet_init` autostart entry is not limited to
   KDE. Start Brave from the menu or panel: a link opened from an Xfce app may start it
   without the flag. Rerunning `xrdp-brave.sh` rewrites the launcher and drops the flag.

3. Back up the two session files:

   ```
   cp ~/.xsession ~/.xsession.pre-xfce
   sudo cp /etc/xrdp/startwm.sh /etc/xrdp/startwm.sh.pre-xfce
   ```

## Phase B: switch, over SSH after logging out of RDP

4. Check that no desktop session is left. This must print nothing:

   ```
   pgrep -a -u "$USER" 'plasmashell|xfconfd'
   ```

5. Point both session files at Xfce. Only the desktop lines change, so the `xrdp-lean`
   lines in `startwm.sh` (renice, no DPMS) stay:

   ```
   sed -i -e 's/^export XDG_SESSION_DESKTOP=KDE$/export XDG_SESSION_DESKTOP=xfce/' \
          -e 's/^export XDG_CURRENT_DESKTOP=KDE$/export XDG_CURRENT_DESKTOP=XFCE/' \
          -e 's/^exec startplasma-x11$/exec startxfce4/' ~/.xsession
   sudo sed -i -e 's/^export XDG_SESSION_DESKTOP=KDE$/export XDG_SESSION_DESKTOP=xfce/' \
               -e 's/^export XDG_CURRENT_DESKTOP=KDE$/export XDG_CURRENT_DESKTOP=XFCE/' \
               /etc/xrdp/startwm.sh
   grep -E 'XDG_.*DESKTOP|^exec' ~/.xsession /etc/xrdp/startwm.sh
   ```

6. Apply the Xfce settings. The scripts see `startxfce4` in `~/.xsession` and take their Xfce
   branch. `xrdp-lean.sh` writes the same xrdp.ini values again, so xrdp needs no restart.
   Do not run `xrdp-setup.sh`: it rebuilds xrdp, which is not needed here.

   ```
   cd ~/xrdp-tune
   sudo ./xrdp-lean.sh "$USER" && sudo ./xrdp-ugly.sh "$USER" && sudo ./xrdp-flameshot.sh "$USER"
   ```

7. Reconnect over RDP and check:
   - Dragging a window shows a wireframe outline; the window redraws on release.
   - Ctrl+Alt+Shift+P opens Flameshot; Enter copies the region to the client clipboard.
   - The wallpaper is solid black and the theme is dark.
   - Brave is still logged in to your sites.
   - `ps -o pid,ni,comm -C xrdp,Xorg,xrdp-chansrv,xfwm4` shows nice -10 / -5 / -5 / 0.

## Rollback

Log out of RDP, then over SSH:

```
cp ~/.xsession.pre-xfce ~/.xsession
sudo cp /etc/xrdp/startwm.sh.pre-xfce /etc/xrdp/startwm.sh
```

Reconnect and Plasma is back. Xfce keeps its settings in `~/.config/xfce4/` and never touched
the KDE configuration. To remove Xfce completely:

```
sudo apt-get remove xfce4 xfce4-terminal mousepad xfce4-clipman
```

Review the list before running `apt-get autoremove`, so that it does not take packages you
still use. The Brave flag can stay: it is harmless under KDE.
