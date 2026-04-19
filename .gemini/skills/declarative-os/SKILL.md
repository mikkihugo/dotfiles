# SKILL: Declarative OS (Nix & Home Manager)

Manage reproducible configurations and environments using Nix, NixOS, and Home Manager.

## Overview
This skill provides guidance on defining and applying declarative system and user configurations. It covers Flakes, Home Manager modules, and Nix-based toolchain management.

## Capabilities
- **Configuration Application**: Use `hms` (home-manager switch) to apply user configs.
- **Flake Management**: Update `flake.lock` and manage inputs.
- **Module Design**: Create and modify Nix modules for specific tools (OpenClaw, Shell, etc.).
- **Reproducibility**: Ensure environments are consistent across different machines (WSL, servers, laptops).

## Usage Guidelines

### 1. Applying Changes
Always apply changes after modifying `.nix` files in the dotfiles repository.
- `hms` (alias for `home-manager switch --flake .#default`)

### 2. Module Updates
When adding a new tool or service:
1. Create or update a module in `home/modules/`.
2. Reference the module in `home/home.nix`.
3. Use `sops-nix` for managing secrets within the configuration.

### 3. Dependency Management
Use the Nix flake to manage versions of CLI tools and libraries.
- `nix flake update` to bump all dependencies.

## Common Commands
| Task | Command |
| :--- | :--- |
| Apply Config | `hms` |
| Update Lockfile | `nix flake update` |
| List Installed | `nix-env -q` |
| Clean Store | `nix-collect-garbage -d` |

## Best Practices
- **GitOps for Dots**: Always commit changes to the dotfiles repo before applying them.
- **Atomic Modules**: Keep Nix modules focused on a single tool or capability.
- **Secrets Management**: Never hardcode secrets in Nix files. Use `sops-nix` and reference the secret path.
- **Role-Based Config**: Use machine roles to conditionally enable or disable modules (e.g., `enableOpenclawNode`).
