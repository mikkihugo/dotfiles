{
  pkgs,
  lib,
  ...
}: let
  # The nixpkgs mise is the bootstrap, not the thing that runs day to day.
  #
  # nixpkgs' mise build writes $out/lib/mise/.disable-self-update, so
  # `mise self-update` refuses to replace the binary, and the Nix store is
  # read-only anyway. Day-to-day currency is operator `mise install` /
  # `mise upgrade` against config/mise/config.toml (mise listed under [tools]
  # via packslip:github.com/jdx/mise). No user timer auto-upgrades tools —
  # the previous mise-auto-update.timer failed on signed-release verification
  # and was removed.
  #
  # The packslip backend is the upstream-preferred one for signed releases: it
  # verifies the publisher's signature against the project identity the name
  # implies and pins the signer it accepted, so a later release from another
  # signer is refused instead of silently trusted.
  #
  # mise's own shim cannot do this job. Every entry in
  # ~/.local/share/mise/shims is a symlink to the mise dispatcher that mise
  # found on PATH, and that dispatcher runs itself rather than dispatching to
  # the `mise` tool — so a `mise` shim never yields the managed binary.
  #
  # The managed binary therefore needs its own PATH entry ahead of the nixpkgs
  # copy: ~/.local/bin precedes the shim farm (home.sessionPath) and
  # ~/.nix-profile/bin. The entry must be a symlink to the managed ELF, not a
  # wrapper script: mise resolves the dispatcher for its shim farm from PATH,
  # and a script there would leave every shim pointing at a bash wrapper that
  # drops the tool name, breaking argv[0] dispatch for droid, node and the
  # rest. The symlink target is the mutable `latest` alias, so `mise upgrade`
  # moves the underlying install without the symlink going stale.
  #
  # The nixpkgs copy stays reachable at ~/.nix-profile/bin/mise and remains the
  # bootstrap that installs the first managed copy.
  managedMisePath = "$HOME/.local/share/mise/installs/mise/latest/bin/mise";

  # Point ~/.local/bin/mise at the managed binary and re-point the shim farm
  # at it. Idempotent: a no-op when the symlink already resolves correctly.
  linkManagedMise = pkgs.writeShellScript "link-managed-mise" ''
    set -euo pipefail

    managed="${managedMisePath}"
    if [ ! -x "$managed" ]; then
      # No managed install yet: the nixpkgs bootstrap installs the first one.
      echo "link-managed-mise: no managed mise at $managed" >&2
      exit 0
    fi

    mkdir -p "$HOME/.local/bin"
    if [ ! -L "$HOME/.local/bin/mise" ] ||
       [ "$(${pkgs.coreutils}/bin/readlink "$HOME/.local/bin/mise")" != "$managed" ]; then
      ${pkgs.coreutils}/bin/rm -f "$HOME/.local/bin/mise"
      ${pkgs.coreutils}/bin/ln -s "$managed" "$HOME/.local/bin/mise"
    fi

    # The shim farm points at whichever mise is on PATH. Re-point it now that
    # ~/.local/bin/mise is the managed binary, so the shims keep argv[0]
    # dispatch against the same mise the shell runs.
    PATH="$HOME/.local/bin:$PATH" "$managed" reshim --force >/dev/null 2>&1 || true
  '';
in {
  # A fresh activation must converge on the managed mise too: the symlink
  # target is a mutable path, so it cannot be a declarative home.file link.
  #
  # Runs after retireMisePython, because any mise invocation re-points the shim
  # farm at the mise it finds on PATH. This step has to be the last one that
  # touches mise, or the shim farm keeps pointing at the nixpkgs binary.
  home.activation.linkManagedMise =
    lib.hm.dag.entryAfter [
      "installPackages"
      "retireMisePython"
    ] ''
      ${linkManagedMise}
    '';
}
