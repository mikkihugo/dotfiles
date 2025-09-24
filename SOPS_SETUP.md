# SOPS Integration for Existing Dotfiles Architecture

Your dotfiles already have a perfect structure! SOPS integrates seamlessly:

## Current Architecture (Unchanged)
- **Files in `.dotfiles`** → symlinked to `$HOME` via profiles
- **`shell/shared/env.sh`** → loads environment variables
- **Nix flake** → provides dev shell with tools

## SOPS Integration (Fits Existing Pattern)

1. **Enter Nix development shell**:
   ```bash
   cd ~/.dotfiles
   nix develop
   ```

2. **Generate your age key**:
   ```bash
   # Get your public age key (put this in .sops.yaml)
   age-keygen

   # Generate private age key (keep this local!)
   ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
   chmod 600 ~/.config/sops/age/keys.txt
   ```

3. **Update .sops.yaml with your public age key**:
   Replace `age1placeholder_replace_with_your_actual_age_key` with the output from `age-keygen`

4. **Create encrypted secrets from template**:
   ```bash
   cp secrets/shared.yaml.template secrets/shared.yaml
   sops secrets/shared.yaml  # This will encrypt it
   ```

5. **Migrate from your current env files**:
   Copy values from `~/.env_tokens`, `~/.env_repos`, etc. into the SOPS editor

## Commands Available in Nix Shell

- `age-keygen` - Show your public age key
- `secrets-edit` - Edit encrypted secrets
- `secrets-view` - View decrypted secrets (for debugging)
- `sops secrets/tokens.yaml` - Edit specific secrets file

## Security Model

✅ **Safe to commit** (encrypted in git):
- `.sops.yaml` - Contains public keys only
- `secrets/*.yaml` - Encrypted secret files

❌ **Never commit** (stays local):
- `~/.config/sops/age/keys.txt` - Your private decryption key

## Migration from Gist System

1. Keep gist sync running during transition
2. Set up SOPS as described above
3. Test that secrets decrypt properly
4. Disable systemd timer: `systemctl --user disable env-sync.timer`
5. Remove old env files: `rm ~/.env_tokens ~/.env_repos`

## Per-Machine Setup

On new machines:
1. Clone dotfiles: `git clone <your-repo> ~/.dotfiles`
2. Copy your SSH key to the new machine
3. Run the age key generation commands above
4. Enter `nix develop` - secrets automatically available!