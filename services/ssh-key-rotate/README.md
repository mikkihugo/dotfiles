# ssh-key-rotate

Monthly ed25519 rotation for `mhugo@hugo.dk`.

## What it does

1. Generates a fresh `ed25519` keypair.
2. Pushes the new pubkey into lldap's `sshPublicKey` attribute via GraphQL — all
   servers running sshd+LDAP `AuthorizedKeysCommand` see it instantly.
3. Updates `~/.dotfiles/secrets/api-keys.yaml` (SOPS-encrypted).
4. Writes new private key to `~/.ssh/mhugo_hugodk_ed25519`.
5. Commits + pushes the SOPS diff to `github.com/mikkihugo/dotfiles`.

## Install

The systemd user units are picked up automatically by home-manager if you
enable them in `home/home.nix`. Minimal enablement (see example below) —
otherwise:

```sh
mkdir -p ~/.config/systemd/user
ln -sf ~/.dotfiles/services/ssh-key-rotate/rotate.service ~/.config/systemd/user/mhugo-ssh-rotate.service
ln -sf ~/.dotfiles/services/ssh-key-rotate/rotate.timer   ~/.config/systemd/user/mhugo-ssh-rotate.timer
systemctl --user daemon-reload
systemctl --user enable --now mhugo-ssh-rotate.timer
```

Verify timer:

```sh
systemctl --user list-timers --all | grep mhugo-ssh-rotate
```

## Run manually

```sh
~/.dotfiles/services/ssh-key-rotate/rotate.sh
```

## Rollback

The previous key is in git history. To roll back:

```sh
git -C ~/.dotfiles log --oneline --follow secrets/api-keys.yaml   # find commit before rotation
git -C ~/.dotfiles checkout <pre-rotation-SHA> -- secrets/api-keys.yaml
# Then re-upload the OLD pubkey to lldap (rotation script does forward rolls only).
```

## Caveats

- Laptop must be online at trigger time. `Persistent=true` makes systemd
  catch up on the next boot if it missed the window.
- Host-level `AuthorizedKeysCommand` must be wired (see
  `hosts/_shared/sshd/ldap-keys.sh`) — otherwise sshd still reads
  `~/.ssh/authorized_keys` and the new key never takes effect.
