#!/bin/bash
# Firefox (.deb from Mozilla's apt repo, not the snap), tuned for a GPU-less VPS behind xrdp.
# Run: sudo ./xrdp-firefox.sh
# Never restarts xrdp. Close Firefox first; policies apply at its next start.
#
# Package: Mozilla's apt repo, pinned above Ubuntu's snap transitional package. The .deb starts
#   faster and uses less RAM than the snap; unattended-upgrades also pulls its security updates.
# Policies (/etc/firefox/policies/policies.json, every user, see about:policies):
#   hardware acceleration off   no GPU: software WebRender only, no GL or VA-API probing
#   autoplay off, new notification requests blocked: fewer surprise frames
#   blank home page and new tab, no Firefox Home feeds
#   telemetry, studies, Pocket, recommendations, onboarding off: less background traffic
# Preferences (set through the policy as defaults, so about:config can still change them):
#   general.smoothScroll false          one frame per scroll step, not an animated glide
#   ui.prefersReducedMotion 1           Firefox UI and sites that honour it drop animations
#   browser.tabs.unloadOnLowMemory      inactive tabs are unloaded when RAM runs low
#   dom.ipc.processCount 2              fewer shared content processes (site isolation stays on)
#   browser.sessionstore.interval 60 s  session written to disk every minute, not every 15 s
#   browser.ml.* off                    no local AI models (link previews, tab grouping, chatbot)
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

echo "== Installing Firefox (apt repo packages.mozilla.org)"
# Same keyring, fingerprint check, .sources file and pin as Mozilla's own Debian/Ubuntu install
# instructions (support.mozilla.org/kb/install-firefox-linux), curl in place of wget.
DEBIAN_FRONTEND=noninteractive apt-get install -y curl gnupg
install -d -m 0755 /etc/apt/keyrings
# The key goes in place only once its fingerprint matches the one Mozilla publishes.
MOZ_FPR=35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3
KEY_TMP=$(mktemp)
trap 'rm -f "$KEY_TMP"' EXIT
curl -fsSLo "$KEY_TMP" https://packages.mozilla.org/apt/repo-signing-key.gpg
FPR=$(gpg --show-keys --with-colons "$KEY_TMP" | awk -F: '$1 == "fpr" {print $10; exit}')
if [ "$FPR" != "$MOZ_FPR" ]; then
  echo "Mozilla key fingerprint mismatch: got '$FPR', expected $MOZ_FPR. Nothing changed." >&2
  exit 1
fi
install -m 0644 "$KEY_TMP" /etc/apt/keyrings/packages.mozilla.org.asc
cat > /etc/apt/sources.list.d/mozilla.sources <<'EOF'
Types: deb
URIs: https://packages.mozilla.org/apt
Suites: mozilla
Components: main
Signed-By: /etc/apt/keyrings/packages.mozilla.org.asc
EOF
# Priority 1000 lets the Mozilla build replace Ubuntu's "1:1snap" transitional package,
# which has a higher version only because of its epoch. The second stanza is Mozilla's Ubuntu
# snap pin: Ubuntu's firefox package is never a candidate, so nothing pulls the snap back.
# Mozilla's page writes it with a separate tee to the same file, which would drop the first
# stanza; both go in one file here.
cat > /etc/apt/preferences.d/mozilla <<'EOF'
Package: *
Pin: origin packages.mozilla.org
Pin-Priority: 1000

Package: firefox
Pin: release o=Ubuntu
Pin-Priority: -1
EOF
# Not on Mozilla's page: lets unattended-upgrades install Firefox security releases.
echo 'Unattended-Upgrade::Origins-Pattern {"site=packages.mozilla.org";};' \
  > /etc/apt/apt.conf.d/51unattended-upgrades-firefox
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-downgrades firefox

echo "== Policies: /etc/firefox/policies/policies.json"
mkdir -p /etc/firefox/policies
cat > /etc/firefox/policies/policies.json <<'EOF'
{
  "policies": {
    "HardwareAcceleration": false,
    "Permissions": {
      "Autoplay": { "Default": "block-audio-video" },
      "Notifications": { "BlockNewRequests": true }
    },
    "Homepage": { "URL": "about:blank" },
    "NewTabPage": false,
    "DisableTelemetry": true,
    "DisableFirefoxStudies": true,
    "DisablePocket": true,
    "DontCheckDefaultBrowser": true,
    "UserMessaging": {
      "ExtensionRecommendations": false,
      "FeatureRecommendations": false,
      "MoreFromMozilla": false,
      "SkipOnboarding": true
    },
    "Preferences": {
      "general.smoothScroll": { "Value": false, "Status": "default" },
      "ui.prefersReducedMotion": { "Value": 1, "Status": "default" },
      "browser.tabs.unloadOnLowMemory": { "Value": true, "Status": "default" },
      "dom.ipc.processCount": { "Value": 2, "Status": "default" },
      "browser.sessionstore.interval": { "Value": 60000, "Status": "default" },
      "browser.ml.enable": { "Value": false, "Status": "default" },
      "browser.ml.chat.enabled": { "Value": false, "Status": "default" }
    }
  }
}
EOF
chmod 644 /etc/firefox/policies/policies.json

# A snap Firefox would keep its own menu entry and profile; it is left alone.
if command -v snap >/dev/null 2>&1 && snap list firefox >/dev/null 2>&1; then
  echo "Note: the snap Firefox is still installed, with its own menu entry and profile"
  echo "  (~/snap/firefox). /usr/bin/firefox is now the .deb. With every Firefox closed, copy"
  echo "  the profile as each desktop user (Mozilla's data migration step), then 'firefox -P':"
  echo "    mkdir -p ~/.mozilla/firefox/ && cp -a ~/snap/firefox/common/.mozilla/firefox/* ~/.mozilla/firefox/"
  echo "  Then remove the snap: sudo snap remove firefox"
fi

echo
firefox --version || true
echo "Done. Close Firefox if it is running, then start it again."
echo "Check: about:policies lists the policies, about:support Graphics shows WebRender (Software)."
echo "Rollback: rm /etc/firefox/policies/policies.json; apt-get remove firefox;"
echo "  rm /etc/apt/sources.list.d/mozilla.sources /etc/apt/preferences.d/mozilla"
echo "  /etc/apt/apt.conf.d/51unattended-upgrades-firefox /etc/apt/keyrings/packages.mozilla.org.asc."
