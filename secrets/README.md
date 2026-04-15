# Secrets

Encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://age-encryption.org).
All files require an authorized age key to decrypt.

## Files

| File | Contents |
|------|----------|
| `api-keys.yaml` | LLM API keys (gateway, claude, google, deepseek, kimi, openrouter, xai, groq, minimax, longcat) |
| `hetzner-ssh.yaml` | Hetzner server SSH keypair |
| `mail.hugo.dk.yaml` | mail.hugo.dk server credentials |

## Setup

Keys are derived from your SSH key:
```bash
ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
```

## Edit a secret

```bash
cd ~/.dotfiles
sops secrets/api-keys.yaml    # opens in $EDITOR, saves encrypted
```

## Add a new authorized key

1. Get the age pubkey: `ssh-to-age -i ~/.ssh/id_ed25519.pub`
2. Add it to `.sops.yaml` keys list
3. Re-encrypt all files: `sops updatekeys secrets/api-keys.yaml`
