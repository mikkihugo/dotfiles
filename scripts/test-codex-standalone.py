#!/usr/bin/env python3
"""Verify Home Manager does not own Codex runtime configuration or lifecycle."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]
for name, tokens in {
    'home/home.nix': ['modules/codex-managed-daemon.nix', 'modules/codex-thread-gc.nix', 'CODEX_SSH_SKIP_APP_SERVER_BOOT'],
    'home/modules/activation.nix': ['seedMutableCodexConfig', 'applySharedCodexPreferences', 'removeRetiredCodexAgentRoles'],
    'home/modules/files.nix': ['".codex/'],
    'home/modules/ai-tools.nix': ['".local/bin/codex-code-mode-host"'],
    'home/modules/shell.nix': ['codex-save-prefs'],
}.items():
    content = (root / name).read_text()
    for token in tokens:
        assert token not in content, f'{name} still manages {token}'
print('Codex standalone Home Manager ownership: ok')
