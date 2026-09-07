# Claude-specific notes for .dotfiles

See [AGENTS.md](./AGENTS.md) for the canonical repo guide. This file is
short — Claude-specific reminders only.

Global cross-cutting behavior (codex-rescue policy, model tiering,
working style) lives in `~/.claude/CLAUDE.md`, not here — don't duplicate
it in this file.

## `hms` shorthand

See AGENTS.md § "Applying changes" for the canonical description of the
`hms` alias (`home-manager switch` for this host, no host argument).
Run it after editing anything under `config/` or `home/`; bare
`home-manager switch` recurses into `~` and is unsafe.
