{
  config,
  lib,
  pkgs,
  hostname ? "",
  ...
}: let
  shortHost =
    if hostname != ""
    then hostname
    else "mhugo";
  backupHost =
    if shortHost == "cc-de-nue-k3s-03"
    # Borg repo path + archive prefix: keep "nue03" (the existing repo name);
    # renaming it would start a new, empty repo. SSH uses the full name.
    then "nue03"
    else shortHost;
  homeDir = "/home/mhugo";
  keyPath = "${homeDir}/.ssh/storagebox-backup";
  sshCommand = "${pkgs.openssh}/bin/ssh -i ${keyPath} -p 23 -o BatchMode=yes -o StrictHostKeyChecking=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -o ControlMaster=no -o ControlPath=none -o ControlPersist=no";
  hotSourcePassphrasePath = config.sops.secrets.borg_hot_source_passphrase.path;
  commonConfig = {
    source_directories = [homeDir];
    exclude_patterns = [
      "${homeDir}/.cache"
      # Lane worktrees: hundreds of full checkouts, walked by every daily run
      # (a 2026-10-24 fsn1 run passed 4h). The nightly worktrees-* jobs back
      # them up to the same storage boxes.
      "${homeDir}/code/worktrees"
      "${homeDir}/**/.cache"
      "${homeDir}/code/worktrees/**/target"
      "${homeDir}/.local/share/singularity-engine/workspaces/*/root-*/mix"
      "${homeDir}/.local/share/singularity-engine/workspaces/*/root-*/hex"
      "${homeDir}/.local/share/singularity-engine/workspaces/*/root-*/rebar3"
      "${homeDir}/.local/share/singularity-engine/workspaces/*/root-*/erlang"
      "${homeDir}/.local/share/singularity-engine/workspaces/*/root-*/python"
      "${homeDir}/.local/share/singularity-engine/workspaces/*/root-*/node"
      "${homeDir}/.local/share/singularity-engine/workspaces/*/root-*/direnv"
      "${homeDir}/.local/state/singularity-engine/workspaces/*/root-*/mix"
      "${homeDir}/.local/state/singularity-engine/workspaces/*/root-*/hex"
      "${homeDir}/.local/state/singularity-engine/workspaces/*/root-*/rebar3"
      "${homeDir}/.local/state/singularity-engine/workspaces/*/root-*/erlang"
      "${homeDir}/.local/state/singularity-engine/workspaces/*/root-*/python"
      "${homeDir}/.local/state/singularity-engine/workspaces/*/root-*/node"
      "${homeDir}/.local/state/singularity-engine/workspaces/*/root-*/direnv"
      "${homeDir}/.kube/cache"
      "${homeDir}/.local/share/Trash"
      "${homeDir}/.local/share/baloo"
      "${homeDir}/.local/share/bun/install/cache"
      "${homeDir}/.local/share/containers/cache"
      "${homeDir}/.local/share/containers/storage"
      "${homeDir}/.local/share/mise/downloads"
      "${homeDir}/.local/share/mise/installs"
      "${homeDir}/.local/share/pnpm/store"
      "${homeDir}/.npm"
      "${homeDir}/.cargo/git"
      "${homeDir}/.cargo/registry"
      "${homeDir}/.rustup/downloads"
      "${homeDir}/.rustup/tmp"
      "${homeDir}/.rustup/toolchains"
      "${homeDir}/go/pkg/mod"
      "${homeDir}/**/node_modules"
      "${homeDir}/**/.venv"
      "${homeDir}/**/target"
      "${homeDir}/**/dist"
      "${homeDir}/**/build"
      "${homeDir}/**/.next"
      "${homeDir}/**/.nuxt"
      "${homeDir}/**/.turbo"
      "${homeDir}/**/.direnv"
      "${homeDir}/**/.terraform"
      "${homeDir}/**/__pycache__"
      "${homeDir}/**/.pytest_cache"
      "${homeDir}/**/.mypy_cache"
      "${homeDir}/**/.ruff_cache"
      "${homeDir}/**/.repowise"
      "${homeDir}/**/.gradle/caches"
      "${homeDir}/**/.m2/repository"
      "${homeDir}/**/coverage"
      "${homeDir}/**/result"
      "${homeDir}/**/result-*"
      # VCS object stores are not backed up (operator 2026-10-17: "we dont need packs -
      # i just want source docs etc"). Committed history lives on Forgejo; the working
      # copies of every checkout and worktree are still captured as plain files.
      "${homeDir}/**/.git"
      "${homeDir}/**/.jj"
      "${homeDir}/**/_build"
      "${homeDir}/.antigravity-ide-server/data/logs"
      "${homeDir}/vendors"
      "${homeDir}/Downloads"
      "${homeDir}/.local/share/containers"
      "${homeDir}/.local/share/jcode"
      "${homeDir}/.jcode"
      "${homeDir}/.local/share/Steam"
      "${homeDir}/.local/share/lutris"
      "${homeDir}/.config/*/Cache"
      "${homeDir}/.config/*/CachedData"
      "${homeDir}/.config/*/blob_storage"
      "${homeDir}/.mozilla/firefox/*/cache2"
      "${homeDir}/.local/share/zed"
      "${homeDir}/.local/share/nvim/swap"
      "${homeDir}/.local/share/nvim/backup"
      "${homeDir}/.local/share/nvim/view"
      "${homeDir}/.local/share/recently-used.xbel"
      "${homeDir}/.local/share/mc"
      "${homeDir}/.local/share/nano"
      "${homeDir}/.local/share/wget-hsts"
      "${homeDir}/.bash_history"
      "${homeDir}/.zsh_history"
      "${homeDir}/.python_history"
      "${homeDir}/.lesshst"
      "${homeDir}/.viminfo"
      "${homeDir}/.wget-hsts"
      "${homeDir}/.codex"
      "${homeDir}/.cursor"
      "${homeDir}/.claude"
      "${homeDir}/.vscode-server"
      "${homeDir}/.gemini"
      "${homeDir}/.kimi-code"
      "${homeDir}/.copilot"
      "${homeDir}/.qoder"
      "${homeDir}/store2-nixos-image"
    ];
    exclude_if_present = [".nobackup"];
    bootstrap.store_config_files = false;
    ssh_command = sshCommand;
    compression = "lz4";
    # Keep Borg's default chunking explicit so cache/repository behavior is stable.
    chunker_params = "buzhash,19,23,21,4095";
    # Build churn changes ctime/inode; mtime+size avoids re-reading unchanged files.
    files_cache = "mtime,size";
    exclude_caches = true;
    extra_borg_options.create = "--upload-buffer 256 --upload-ratelimit 0";
    borg_exit_codes = [
      {
        code = 105;
        treat_as = "warning";
      }
    ];
    keep_daily = 7;
    keep_weekly = 4;
    keep_monthly = 12;
    checks = [
      {
        name = "repository";
        frequency = "2 weeks";
      }
      {
        name = "archives";
        frequency = "4 weeks";
      }
    ];
  };
  targets = {
    hel1 = {
      description = "HEL1";
      schedule = "*-*-* 02:00:00";
      path = "ssh://u579183-sub5@u579183-sub5.your-storagebox.de:23/./borg/${backupHost}";
    };
    fsn1 = {
      description = "FSN1";
      schedule = "*-*-* 04:00:00";
      path = "ssh://u602823-sub5@u602823-sub5.your-storagebox.de:23/./borg/${backupHost}";
    };
  };
  borgmaticConfig = name: target:
    commonConfig
    // {
      repositories = [
        {
          inherit (target) path;
          label = "storagebox-${name}";
        }
      ];
      archive_name_format = "${backupHost}-${name}-{now:%Y-%m-%dT%H:%M:%SZ}";
    };
  configPath = name: "${homeDir}/.config/borgmatic.d/home-emergency-${name}.yaml";
  hotSourceDirectories = [
    "${homeDir}/.dotfiles"
    "${homeDir}/.dotfiles-worktrees"
    "${homeDir}/code"
    "${homeDir}/workspaces"
    "${homeDir}/backups"
    "/srv/infra"
    # Keep every listed path existing: borgmatic refuses to run when ANY source path is
    # missing (the dropped ${homeDir}/.cache/engine-jj-git-store broke every hot-source job
    # from ~2026-10-07 until 2026-10-10).
    # Scope (operator 2026-10-17): working-copy source and docs of every checkout and
    # worktree only - no VCS object stores (.git/.jj packs) and no build output. Committed
    # history is recoverable from Forgejo; what only exists here is the working tree.
  ];
  hotSourceExcludes = [
    # regex, not **/.cache: a fm/sh glob also excludes a source root that lives under .cache (the engine jj store below)
    "re:(^|/)\\.cache$"
    "**/.direnv"
    "**/node_modules"
    "**/target"
    "**/dist"
    "**/build"
    "**/.venv"
    "**/__pycache__"
    "**/.pytest_cache"
    "**/.mypy_cache"
    "**/.ruff_cache"
    "**/.terraform"
    "**/result"
    "**/result-*"
    "**/_build"
    # VCS object stores (packs): not wanted. This also drops the ~47 GB Engine jj store
    # (code/singularity-engine/.jj) and its .git bind mount, which every cycle used to walk.
    "**/.git"
    "**/.jj"
    # superseded engine stores: the broken 2026-09-03 store, and the one-off
    # pre-repair copy that the repair it predates already replaced.
    "${homeDir}/code/singularity-engine/.jj.broken-20260903"
    "${homeDir}/backups/singularity-engine/primary-repair-20260923-07081f20"
    # jcode lane checkouts each carry a full copy of the canonical assets/ tree
    # (demos + readme media, 25 files / 177332713 B, byte-identical across lanes
    # and to code/jcode/assets). The canonical copy stays in the archive.
    "${homeDir}/code/worktrees/jj/jcode/*/assets"
  ];
  # ~/code/worktrees holds hundreds of full lane checkouts (2026-10-24: 229
  # Engine, 163 jcode, 86 infra). Walking them every cycle kept each hot-source
  # run at 58-83min on the IOPS-capped devbox disk, so the 30min schedule ran
  # back to back and saturated it. Hot-source skips them; worktreeConfig backs
  # them up once a night instead (operator 2026-10-24).
  worktreeRoot = "${homeDir}/code/worktrees";
  hotSourceConfig = name: target: {
    source_directories = hotSourceDirectories;
    repositories = [
      {
        # v3 (2026-10-17): fresh repository for the source-only scope. hot-source-v2 still
        # holds archives with VCS packs; delete it once v3 has verified archives on both sites.
        path = "${lib.removeSuffix "/${backupHost}" target.path}/hot-source-v3/${backupHost}";
        label = "hot-source-${name}";
        make_parent_directories = true;
      }
    ];
    archive_name_format = "${backupHost}-hot-source-${name}-{now:%Y-%m-%dT%H:%M:%SZ}";
    # explicit so prune never counts the nightly worktree archives in this repo
    match_archives = "sh:${backupHost}-hot-source-${name}-*";
    exclude_patterns = hotSourceExcludes ++ [worktreeRoot];
    exclude_if_present = [".nobackup"];
    # cargo writes CACHEDIR.TAG into target/; skips cache dirs the glob list misses
    exclude_caches = true;
    # build churn changes ctime/inode; borg's default ctime,size,inode files cache then misses and rehashes
    files_cache = "mtime,size";
    bootstrap.store_config_files = false;
    ssh_command = sshCommand;
    compression = "lz4";
    extra_borg_options.create = "--upload-buffer 256 --upload-ratelimit 0";
    keep_hourly = 96;
    keep_daily = 14;
    keep_weekly = 8;
    keep_monthly = 12;
    # Hot-source has no database hooks, so borgmatic's unconditional
    # pre-create validation pass (borgmatic/borg/create.py
    # validate_planned_backup_paths -> "borg create --dry-run --list",
    # meant only to confirm the runtime hook directory survives excludes)
    # buys nothing here. On these large trees (code/, /srv/infra) it
    # re-walks the whole source set a second time before the real create
    # even starts: observed 2026-09-24 as a ~21min gap between borgmatic's
    # "Creating archive" log line and borg's own "Creating archive at ..."
    # banner in one hot-source-hel1 cycle, and a separate ~53min gap
    # (service start to the real `borg create` process appearing in ps) in
    # another. That is most of the 60min RuntimeMaxSec budget spent before
    # the real create even begins, which is why every observed cycle ended
    # "Failed with result 'timeout'" (journalctl --user -u
    # hot-source-hel1.service). Skip the redundant pass.
    unsafe_skip_path_validation_before_create = true;
  };
  worktreeConfig = name: target:
    (hotSourceConfig name target)
    // {
      source_directories = [worktreeRoot];
      archive_name_format = "${backupHost}-worktrees-${name}-{now:%Y-%m-%dT%H:%M:%SZ}";
      match_archives = "sh:${backupHost}-worktrees-${name}-*";
      exclude_patterns = hotSourceExcludes;
      keep_hourly = 0;
      keep_daily = 14;
      keep_weekly = 8;
      keep_monthly = 6;
    };
  hotConfigPath = name: "${homeDir}/.config/borgmatic.d/hot-source-${name}.yaml";
  worktreeConfigPath = name: "${homeDir}/.config/borgmatic.d/worktrees-${name}.yaml";
  # One lock for hot-source and worktree runs on both sites, so no two borg
  # walks of this disk ever overlap. Hot-source skips (-n, exit 75) when the
  # lock is held; the nightly worktree run waits for it.
  borgRunner = label: configPath: lockMode:
    pkgs.writeShellScript "borgmatic-${label}" ''
      set -euo pipefail
      lock="$XDG_RUNTIME_DIR/borgmatic-hot-source.lock"
      exec ${pkgs.util-linux}/bin/flock ${lockMode} -E 75 "$lock" ${pkgs.bash}/bin/bash -c '
        set -euo pipefail
        config="$1"
        borgmatic="$2"
        passphrase_file="$3"
        test -s "$passphrase_file"
        export BORG_PASSPHRASE="$(< "$passphrase_file")"
        "$borgmatic" --config "$config" repo-info --verbosity -1 >/dev/null 2>&1 ||
          "$borgmatic" --config "$config" repo-create --encryption repokey --verbosity 1
        exec "$borgmatic" --config "$config" create prune compact --verbosity 1
      ' _ ${configPath} ${pkgs.borgmatic}/bin/borgmatic ${hotSourcePassphrasePath}
    '';
  hotSourceRunner = name: borgRunner "hot-source-${name}" (hotConfigPath name) "-n";
  worktreeRunner = name: borgRunner "worktrees-${name}" (worktreeConfigPath name) "--wait 21600";
  restoreKeyPackage = pkgs.writeShellScriptBin "storagebox-backup-key-restore" ''
    set -euo pipefail

    export HOME="${homeDir}"
    export BAO_ADDR="''${BAO_ADDR:-http://vault-active.vault.svc.cluster.local:8200}"

    key_path="${keyPath}"
    pub_path="$key_path.pub"

    if [ -s "$key_path" ] && [ -s "$pub_path" ]; then
      exit 0
    fi

    mkdir -p "$HOME/.ssh"
    umask 077
    ${pkgs.openbao}/bin/bao kv get -field=private_key \
      kv/storagebox-mhugo-home-backup-ssh > "$key_path"
    chmod 600 "$key_path"
    ${pkgs.openbao}/bin/bao kv get -field=public_key \
      kv/storagebox-mhugo-home-backup-ssh > "$pub_path"
    chmod 644 "$pub_path"

    known_hosts="$(${pkgs.openbao}/bin/bao kv get -field=known_hosts \
      kv/storagebox-mhugo-home-backup-ssh 2>/dev/null || true)"
    if [ -n "$known_hosts" ]; then
      touch "$HOME/.ssh/known_hosts"
      printf '%s\n' "$known_hosts" | while IFS= read -r line; do
        [ -n "$line" ] || continue
        ${pkgs.gnugrep}/bin/grep -qxF "$line" "$HOME/.ssh/known_hosts" ||
          printf '%s\n' "$line" >> "$HOME/.ssh/known_hosts"
      done
      chmod 644 "$HOME/.ssh/known_hosts"
    fi
  '';
  serializedBackupScript = name:
    pkgs.writeShellScript "home-emergency-backup-${name}-serialized" ''
      set -euo pipefail
      lock="''${XDG_RUNTIME_DIR:-/run/user/$UID}/home-mutable-workspace-sweep.lock"
      echo "home-emergency-backup-${name} waiting for mutable sweep lock: $lock"
      ${pkgs.util-linux}/bin/flock --exclusive --wait 43200 --conflict-exit-code 75 \
        "$lock" ${pkgs.bash}/bin/bash -c \
        '${restoreKeyPackage}/bin/storagebox-backup-key-restore && exec ${pkgs.borgmatic}/bin/borgmatic --config ${configPath name} --verbosity 1' || {
        status=$?
        echo "home-emergency-backup-${name} mutable sweep lock unavailable or backup failed: status=$status lock=$lock" >&2
        exit "$status"
      }
    '';
in
  lib.mkMerge [
    {
      home.packages = [
        pkgs.borgbackup
        pkgs.borgmatic
        pkgs.openssh
        restoreKeyPackage
      ];

      xdg.configFile = lib.mapAttrs' (name: target:
        lib.nameValuePair "borgmatic.d/home-emergency-${name}.yaml" {
          text = builtins.toJSON (borgmaticConfig name target);
        })
      targets;

      systemd.user.services = lib.mapAttrs' (name: target:
        lib.nameValuePair "home-emergency-backup-${name}" {
          Unit = {
            Description = "Back up /home/mhugo to Hetzner Storage Box sub5 ${target.description}";
            After = ["network-online.target"];
            Wants = ["network-online.target"];
            # A Home Manager generation switch must not launch or wait for a
            # full-home backup. The timer remains the sole start authority.
            X-SwitchMethod = "keep-old";
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${serializedBackupScript name}";
            # Keep whole-home borg reads/writes below interactive and build I/O
            # while retaining best-effort scheduling (the disk is not idle).
            IOWeight = 20;
            CPUWeight = 20;
            IOSchedulingClass = "best-effort";
            IOSchedulingPriority = 7;
            Nice = 10;
            IOReadBandwidthMax = "/dev/sda 40M";
            IOWriteBandwidthMax = "/dev/sda 40M";
            # Whole-home reads filled 9.7G+ of page cache, evicting build
            # working sets. MemoryHigh reclaims this job's own cache first;
            # borg's anon memory is far below the ceiling (2026-10-10).
            MemoryHigh = "8G";
            MemoryMax = "16G";
            Environment = [
              "HOME=${homeDir}"
              "BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes"
            ];
          };
        })
      targets;

      systemd.user.timers = lib.mapAttrs' (name: target:
        lib.nameValuePair "home-emergency-backup-${name}" {
          Unit.Description = "Nightly /home/mhugo emergency backup to ${name} (${target.schedule} with 20min jitter)";
          Timer = {
            OnCalendar = target.schedule;
            RandomizedDelaySec = "20min";
            Persistent = true;
            Unit = "home-emergency-backup-${name}.service";
          };
          Install.WantedBy = ["timers.target"];
        })
      targets;
    }
    (lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
      sops.secrets.borg_hot_source_passphrase = {
        key = "borg/hot_source_passphrase";
        mode = "0600";
        sopsFile = ../../secrets/api-keys.yaml;
      };

      xdg.configFile =
        (lib.mapAttrs' (name: target:
          lib.nameValuePair "borgmatic.d/hot-source-${name}.yaml" {
            text = builtins.toJSON (hotSourceConfig name target);
          })
        targets)
        // (lib.mapAttrs' (name: target:
          lib.nameValuePair "borgmatic.d/worktrees-${name}.yaml" {
            text = builtins.toJSON (worktreeConfig name target);
          })
        targets);

      systemd.user.services =
        (lib.mapAttrs' (name: target:
          lib.nameValuePair "hot-source-${name}" {
            Unit = {
              Description = "Back up hot source trees to Hetzner Storage Box ${target.description}";
              After = ["network-online.target"];
              Wants = ["network-online.target"];
              X-SwitchMethod = "keep-old";
            };
            Service = {
              Type = "exec";
              ExecStartPre = "${restoreKeyPackage}/bin/storagebox-backup-key-restore";
              ExecStart = "${hotSourceRunner name}";
              SuccessExitStatus = [75];
              # Was 60min: even with the pre-create validation walk removed
              # (unsafe_skip_path_validation_before_create above), the first
              # cold-cache "create" of these large trees observed 2026-09-24
              # still ran 36+ min before hitting the old ceiling without
              # finishing, so create/prune/compact has apparently never
              # completed once. hotSourceRunner's flock is shared by both
              # hel1 and fsn1 (same lock path for both), so a longer ceiling
              # means whichever target is running can hold that shared lock,
              # and so starve the other, for longer -- that tradeoff is
              # accepted here because the starvation only ends once some
              # create finally completes and seeds the chunk cache, after
              # which subsequent incremental creates should be far faster.
              RuntimeMaxSec = "115min";
              Nice = 19;
              IOSchedulingClass = "idle";
              CPUWeight = 10;
              IOWeight = 10;
              # Same envelope as home-emergency-backup: observed peaks of
              # 11-23G were mostly page cache, not borg anon (2026-10-10).
              MemoryHigh = "4G";
              MemoryMax = "10G";
              Environment = [
                "HOME=${homeDir}"
              ];
            };
          })
        targets)
        // (lib.mapAttrs' (name: target:
          lib.nameValuePair "worktrees-${name}" {
            Unit = {
              Description = "Back up lane worktrees to Hetzner Storage Box ${target.description} (nightly)";
              After = ["network-online.target"];
              Wants = ["network-online.target"];
              X-SwitchMethod = "keep-old";
            };
            Service = {
              Type = "exec";
              ExecStartPre = "${restoreKeyPackage}/bin/storagebox-backup-key-restore";
              ExecStart = "${worktreeRunner name}";
              SuccessExitStatus = [75];
              # waits up to 6h for the shared lock, then walks every worktree
              RuntimeMaxSec = "10h";
              Nice = 19;
              IOSchedulingClass = "idle";
              CPUWeight = 10;
              IOWeight = 10;
              MemoryHigh = "4G";
              MemoryMax = "10G";
              Environment = ["HOME=${homeDir}"];
            };
          })
        targets);

      systemd.user.timers = {
        hot-source-hel1 = {
          Unit.Description = "Hot-source backup to HEL1 every 2 hours (even hours)";
          Timer = {
            OnCalendar = "*-*-* 00/2:00:00";
            RandomizedDelaySec = "2min";
            Persistent = true;
            Unit = "hot-source-hel1.service";
          };
          Install.WantedBy = ["timers.target"];
        };
        hot-source-fsn1 = {
          Unit.Description = "Hot-source backup to FSN1 every 2 hours (odd hours), staggered from HEL1";
          Timer = {
            OnCalendar = "*-*-* 01/2:00:00";
            RandomizedDelaySec = "2min";
            Persistent = true;
            Unit = "hot-source-fsn1.service";
          };
          Install.WantedBy = ["timers.target"];
        };
        worktrees-hel1 = {
          Unit.Description = "Nightly lane-worktree backup to HEL1";
          Timer = {
            OnCalendar = "*-*-* 02:30:00";
            RandomizedDelaySec = "5min";
            Persistent = true;
            Unit = "worktrees-hel1.service";
          };
          Install.WantedBy = ["timers.target"];
        };
        worktrees-fsn1 = {
          Unit.Description = "Nightly lane-worktree backup to FSN1";
          Timer = {
            OnCalendar = "*-*-* 03:30:00";
            RandomizedDelaySec = "5min";
            Persistent = true;
            Unit = "worktrees-fsn1.service";
          };
          Install.WantedBy = ["timers.target"];
        };
      };
    })
  ]
