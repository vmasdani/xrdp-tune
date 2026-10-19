# SSH key-only login, with the key in Bitwarden

Turn off SSH password login so only keys get in, the way AWS boxes work. The private key
lives in Bitwarden, so a new device only needs the vault to log in. Nothing in this guide
needs a `.pem` file: a key is a key whatever the file is called.

The two halves of a key go to different places:

| Half | Where it lives |
|---|---|
| Private key | Bitwarden, plus each client that logs in. Never on the server, never pasted in chat |
| Public key | One line in the server's `~/.ssh/authorized_keys`. Safe to share |

> **Warning:** keep one SSH session to the box open until the last test passes. If key login
> breaks after passwords are off, the provider's web console (VNC) still takes the user
> password, so keep that password strong and stored in Bitwarden too.

## 1. Make the key in Bitwarden

1. In the Bitwarden web vault or desktop app, choose **New** > **SSH key**. Bitwarden
   generates an Ed25519 key pair and stores the private key, public key and fingerprint in
   the item. Name it after the box, for example `ssh biker@vmi`.
2. To keep a key you already have instead, paste its private key into a new SSH key item
   (the import fills in the public key). Use the SSH key item type, not a secure note: a
   note can drop the final newline or add Windows line endings, and ssh then fails to load
   the key.
3. Turn on two-step login for the Bitwarden account. The vault now opens the server.

## 2. Put the public key on the server

Copy the **Public key** field from the item. It is one line starting with `ssh-ed25519`.
On the server, as the login user, add it as a new line in `~/.ssh/authorized_keys` and fix
the permissions:

```
mkdir -p ~/.ssh
echo 'ssh-ed25519 AAAA...paste-the-public-key... ssh biker@vmi' >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
```

One line per key. Removing a line revokes that key.

## 3. Use the key from a client

**Desktop (Windows, macOS, Linux):** use the SSH agent built into the Bitwarden desktop app,
so the private key is never written to disk.

1. Settings > **Enable SSH agent**.
2. Point ssh at it. On Linux and macOS, add to `~/.bashrc` (or `~/.zshrc`):

   ```
   export SSH_AUTH_SOCK=~/.bitwarden-ssh-agent.sock
   ```

   The Snap build of Bitwarden puts the socket at
   `~/snap/bitwarden/current/.bitwarden-ssh-agent.sock`. On Windows, stop and disable the
   "OpenSSH Authentication Agent" service so Bitwarden can take over the agent pipe.
3. `ssh username@host`. Bitwarden asks to approve each use of the key while the vault is
   unlocked.

**Termux (Android):** Bitwarden has no agent there, so copy the private key into a file.

1. Copy the **Private key** field from the item in the Bitwarden app.
2. Paste it into Termux's own home, not `/sdcard` (files there cannot be made private):

   ```
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   nano ~/.ssh/id_ed25519        # paste, keep the newline after the END line
   chmod 600 ~/.ssh/id_ed25519
   ssh-keygen -y -f ~/.ssh/id_ed25519   # prints the public key if the file is intact
   ```

3. Optional: give the file copy a passphrase with `ssh-keygen -p -f ~/.ssh/id_ed25519`, so
   a lost phone does not hand over the key.
4. `ssh username@host`. `id_ed25519` is a default name, so no `-i` is needed. If you do use
   `-i`, give it the private key: pointing it at the `.pub` fails with
   `Load key "...id_ed25519.pub": error in libcrypto: unsupported` and ssh falls back to
   asking for the password.

## 4. Test key login

From a new terminal (keep the old one open):

```
ssh username@host
```

It must log in without asking for the user password. A passphrase prompt for the key itself
is fine.

## 5. Turn off password login

On the server:

```
sudo tee /etc/ssh/sshd_config.d/00-keys-only.conf >/dev/null <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
sudo sshd -t && sudo systemctl reload ssh
sudo sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin)'
```

The last command must print:

```
passwordauthentication no
kbdinteractiveauthentication no
permitrootlogin without-password
```

(`without-password` is the old name for `prohibit-password`.)

The file is named `00-...` on purpose. sshd keeps the first value it reads for each setting,
and `00` sorts before cloud images' `50-cloud-init.conf`, which can set
`PasswordAuthentication yes`, and the drop-ins are read before the main
`sshd_config`. So the file wins without editing anything else.

## 6. Check that passwords are refused

From a new terminal:

```
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no username@host
```

It must fail with `Permission denied (publickey)`. Then log in once more with the key to
confirm that still works.

## New device

Desktop: install Bitwarden, enable the SSH agent (step 3) and log in. Termux: copy the
private key from Bitwarden into `~/.ssh/id_ed25519` (step 3). Nothing changes on the server.

## Undo

```
sudo rm /etc/ssh/sshd_config.d/00-keys-only.conf && sudo systemctl reload ssh
```

This only covers SSH. xrdp on 3389 still takes the password; close it in the firewall and
tunnel RDP over SSH as in the README section "Security: RDP over SSH".
