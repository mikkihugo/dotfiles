# API Token Security

Never commit API tokens, private keys, tunnel tokens, or decrypted SOPS files.

## Storage

- Personal shell/API keys live in `secrets/api-keys.yaml` encrypted with SOPS.
- Shared infrastructure secrets live in OpenBao under the documented `kv/*` paths.
- Machine-local secrets may be exported into the shell at runtime, but generated plaintext files stay gitignored.
- Do not use private gists or ad-hoc checked-in examples as a backup path for secrets.

## Runtime Loading

The shell loader in `shell/bash/bashrc` decrypts `~/.dotfiles/secrets/api-keys.yaml` on demand and exports provider credentials for local tools.

Infrastructure tooling should read from OpenBao directly, for example:

```bash
bao kv get -field=api_token kv/cloudflare
```

## Checks

Run the local secret scanner before committing sensitive changes:

```bash
.scripts/check-secrets.sh
```

If a secret is accidentally committed, rotate it first, then clean the repository history as needed.
