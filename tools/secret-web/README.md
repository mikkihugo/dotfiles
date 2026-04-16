# secret-web

Local React editor for SOPS-managed secret files in `~/.dotfiles/secrets`.

## Run

```bash
cd ~/.dotfiles/tools/secret-web
npm install
npm run dev
```

This starts:
- Vite UI on `http://127.0.0.1:4174`
- local API on `http://127.0.0.1:4310`

## Behavior

- lists every YAML file in `~/.dotfiles/secrets`
- opens and decrypts files via `sops`
- reveals, copies, and edits individual keys
- saves back through `sops -e -i`
- treats `shared.yaml` as the source of truth when you select it
