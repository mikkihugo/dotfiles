# home/modules/engine-worktree-cleanup.nix
#
# Retire stale singularity-engine jj task workspaces on a schedule, through the
# repository's own guarded `repo vcs` verbs.
#
# Why this module exists: this sweep lived as unmanaged plain files
# (~/.local/bin/engine-worktree-cleanup plus hand-written units in
# ~/.config/systemd/user/). On 2026-08-07/08 that copy destroyed 7 REGISTERED jj
# workspaces — a `jj workspace list | grep -q` pipeline under `set -o pipefail`
# read SIGPIPE as "not registered" and rm -rf'd the directory. Nothing in the
# repository described the job, so no review, test, or `hms` could have caught
# it. Home Manager now owns the script and both units, and the script it runs is
# an immutable /nix/store copy that an edit in $HOME cannot change.
{
  config,
  hostname ? "",
  lib,
  pkgs,
  ...
}: let
  homeDir = config.home.homeDirectory;

  cleanupScript = pkgs.writeShellScript "engine-worktree-cleanup" ''
    exec ${pkgs.bash}/bin/bash ${./engine-worktree-cleanup.sh} "$@"
  '';

  # The unit reaches the facade by absolute path with an explicit environment;
  # it does NOT load direnv. In every real timer run before 2026-08-08 the
  # engine's `direnv export bash` nix eval failed ("Boolean setting
  # 'builders-use-substitutes' has invalid value ''", because
  # nix/cache/org-nix-config.sh needs a python3 the unit's PATH lacks) and
  # direnv silently fell back, so the sweep ran with an ambient jj and no facade
  # at all. Verified 2026-08-08: with SE_JJ_BIN set to a jujutsu store path,
  # `bin/repo vcs workspace-list` succeeds on a PATH of only
  # /run/current-system/sw/bin:/usr/bin:/bin.
  servicePath = lib.concatStringsSep ":" [
    "${pkgs.bash}/bin"
    "${pkgs.coreutils}/bin"
    "${pkgs.jujutsu}/bin"
    "/run/current-system/sw/bin"
    "/usr/bin"
    "/bin"
  ];
in
  lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
    # Manual invocation keeps working. `force` is required, not cosmetic: this
    # path holds the old unmanaged script, and without it activation aborts with
    # "would be clobbered" (see check-link-targets.sh forcedPaths).
    home.file.".local/bin/engine-worktree-cleanup" = {
      source = cleanupScript;
      executable = true;
      force = true;
    };

    systemd.user.services.engine-worktree-cleanup = {
      Unit = {
        Description = "Retire stale singularity-engine jj task workspaces via repo vcs";
        # A Home Manager switch must never start this. Without keep-old, every
        # `hms` that changes the unit runs a destructive-by-design sweep at an
        # arbitrary moment, across whatever lanes are live. The timer is the sole
        # start authority.
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${cleanupScript}";
        Environment = [
          "HOME=${homeDir}"
          "PATH=${servicePath}"
          "SE_JJ_BIN=${pkgs.jujutsu}/bin/jj"
        ];
        Nice = 19;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "5min";
      };
    };

    systemd.user.timers.engine-worktree-cleanup = {
      Unit.Description = "Daily singularity-engine workspace sweep";
      Timer = {
        # Was 03,12,21:30 with Persistent=true. Now once daily and without
        # catch-up: the sweep only ever schedules guarded verbs that refuse, so
        # three passes buy nothing, and Persistent replayed a destructive sweep
        # at login — exactly when lanes are being created. A skipped day costs
        # only a stale registration.
        OnCalendar = "*-*-* 04:40";
        Persistent = false;
        RandomizedDelaySec = "15m";
        Unit = "engine-worktree-cleanup.service";
      };
      Install.WantedBy = ["timers.target"];
    };
  }
