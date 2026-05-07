# System Documentation

## Overview

This repository implements the declarative home and machine configuration for the personal infrastructure used by `mhugo`.

The system architecture is centered on:

- `home-manager` for user environment management and dotfiles activation.
- `SOPS + age` for declarative, git-tracked secret encryption.
- `Headscale` as the central self-hosted Tailscale control plane.
- `Tailscale` clients on every machine for private overlay networking.
- `OpenBao` at `app.hugo.dk/vault` for runtime secrets and machine/service auth.
- `Authelia` for human identity and passkey-based login to admin surfaces.

## Host Inventory

### Declared home configurations

The flake defines the following home profiles in `flake.nix`:

- `mikki-bunker` — x86_64 WSL2 desktop with GPU worker capability.
- `mikki-laptop` — aarch64 portable laptop.
- `mhugo` — hostname alias to the current machine, evaluated at runtime.

### Machine roles

Machine-specific behavior is driven by `bootstrap/steps/05-machine-setup.sh` and `home/modules/machine-role.nix`.

The role metadata is stored in:

- `~/.config/dotfiles/machine-role.json`
- `~/.config/dotfiles/machine-role.env`

Supported role-related options:

- `dotfiles.machine.role` — machine purpose string (`laptop`, `workstation`, `worker`, `server`, `general`).
- `dotfiles.machine.enableOpenclawNode` — enable legacy OpenClaw node service.
- `dotfiles.machine.enableHermesProxy` — enable Hermes proxy gateway.
- `dotfiles.machine.validateSudoAccess` — whether bootstrap validates sudo.

Default semantics:

- `workstation` and `worker` roles default `enableHermesProxy=true`.
- `enableHermesProxy` disables legacy OpenClaw during bootstrap by default.

## Network Overlay

### Headscale / Tailscale

This repo uses Headscale as the central coordination server and Tailscale as the overlay VPN client.

Primary configuration lives in:

- `home/modules/tailscale.nix`
- `secrets/api-keys.yaml` under the `tailscale:` key

The activation flow in `home/modules/tailscale.nix`:

1. Installs `tailscale` if missing.
2. Enables and starts `tailscaled`.
3. Reads `tailscale/login_server` and `tailscale/authkey` from decrypted SOPS secrets.
4. Runs `tailscale up --login-server="..." --authkey="..." --operator="$(whoami)" --accept-routes`.

The `login_server` is the central Headscale control plane URL; documentation and repo comments refer to `https://vpn.hugo.dk`.

### Known Tailnet pattern

- `headscale` appears in docs as the control plane.
- `vpn.hugo.dk` is the expected login server address.
- Tailnet-only admin services are accessed over the Tailscale overlay.

## Secrets Model

### Declarative secrets

Declarative secrets are stored in this repo under `secrets/*.yaml` and encrypted with SOPS + age.

- `.sops.yaml` contains recipient metadata.
- `secrets/api-keys.yaml` stores long-lived secrets, authkeys, and service credentials.

This data is used during bootstrap and activation and is not treated as runtime-rotating secrets.

### Runtime secrets

Runtime secrets are handled by OpenBao KV v2 via `BAO_ADDR`.

- `home/home.nix` exports `BAO_ADDR="https://app.hugo.dk/vault"`.
- `home/modules/packages.nix` installs the `openbao` CLI.
- Runtime secrets policy is to fetch with `bao kv get kv/<path>` and to use AppRole/OIDC for auth.

## OpenBao / Vault Integration

The current system is designed around OpenBao as the shared secrets plane.

Key integration points:

- `BAO_ADDR` is exported globally for user shells.
- The `openbao` CLI is installed in every user profile.
- The OpenBao UI is served at `app.hugo.dk/vault`.

The repo currently favors:

- `bao login -method=oidc` for human auth.
- AppRole SecretIDs for machine/service auth.
- `bao kv get` for dynamic runtime secret retrieval.

## Bootstrap Flow

The main installation path is:

1. `./install.sh`
2. `bootstrap/steps/*.sh`
3. `home-manager` activation via `hms`

Bootstrap responsibilities include:

- granting passwordless sudo via `02-sudoers.sh`
- machine role setup via `05-machine-setup.sh`
- home-manager activation and Tailscale join through `home/modules/tailscale.nix`

## Current System State

Current repository structure supporting system configuration:

- `home/home.nix` — root home-manager entrypoint.
- `home/modules/packages.nix` — packages installed for every host.
- `home/modules/tailscale.nix` — Tailnet join logic.
- `home/modules/machine-role.nix` — machine role options.
- `bootstrap/steps/05-machine-setup.sh` — interactive machine role bootstrap.
- `secrets/api-keys.yaml` — SOPS-encrypted keys and service credentials.
- `README.md` / `NEW_MACHINE_SETUP.md` — user-facing onboarding and setup guidance.

This repo does not currently contain Flux GitOps manifests, `flux-system` resources, or a declarative kubeconfig for a Flow k3s cluster. References to `flow` and `k3s` are limited to module comments and documentation notes, not to a self-managed Flux deployment pipeline.

## Operational Notes

- The repo preserves Docker for Mailcow and explicitly avoids moving Mailcow to k3s yet.
- Host-specific names are `mikki-bunker` and `mikki-laptop` with `mhugo` alias support.
- The system is intentionally built to avoid custom control-plane services and keep runtime auth on established products.

## Recommended Next Steps

- Confirm that laptop and bunker both join the Headscale tailnet successfully.
- Verify `bao login -method=oidc` and `bao kv get` on each machine.
- Keep machine role JSON/env in sync after bootstrap.
- Document any additional server hostnames or services as they are brought under the repo.

---

This document is intended to capture the current system architecture and inventory for the dotfiles repo and the underlying networking/auth stack.
