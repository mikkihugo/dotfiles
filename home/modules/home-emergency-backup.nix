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
    then "nue03"
    else shortHost;
  homeDir = "/home/mhugo";
  keyPath = "${homeDir}/.ssh/storagebox-backup";
  sshCommand = "${pkgs.openssh}/bin/ssh -i ${keyPath} -p 23 -o BatchMode=yes -o StrictHostKeyChecking=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=4";
  hotSourcePassphrasePath = config.sops.secrets.borg_hot_source_passphrase.path;
  commonConfig = {
    source_directories = [homeDir];
    exclude_patterns = [
      "${homeDir}/.cache"
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
      "${homeDir}/**/.git"
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
      schedule = "*-*-* 00:00:00";
      path = "ssh://u579183-sub5@u579183-sub5.your-storagebox.de:23/./borg/${backupHost}";
    };
    fsn1 = {
      description = "FSN1";
      schedule = "*-*-* 12:00:00";
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
  ];
  hotSourceExcludes = [
    "**/.cache"
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
  ];
  hotSourceConfig = name: target: {
    source_directories = hotSourceDirectories;
    repositories = [
      {
        path = "${lib.removeSuffix "/${backupHost}" target.path}/hot-source-v2/${backupHost}";
        label = "hot-source-${name}";
        make_parent_directories = true;
      }
    ];
    archive_name_format = "${backupHost}-hot-source-${name}-{now:%Y-%m-%dT%H:%M:%SZ}";
    exclude_patterns = hotSourceExcludes;
    exclude_if_present = [".nobackup"];
    bootstrap.store_config_files = false;
    ssh_command = sshCommand;
    compression = "lz4";
    extra_borg_options.create = "--upload-buffer 256 --upload-ratelimit 0";
    keep_hourly = 96;
    keep_daily = 14;
    keep_weekly = 8;
    keep_monthly = 12;
  };
  hotConfigPath = name: "${homeDir}/.config/borgmatic.d/hot-source-${name}.yaml";
  hotSourceRunner = name:
    pkgs.writeShellScript "borgmatic-hot-source-${name}" ''
      set -euo pipefail
      lock="$XDG_RUNTIME_DIR/borgmatic-hot-source.lock"
      exec ${pkgs.util-linux}/bin/flock -n -E 75 "$lock" ${pkgs.bash}/bin/bash -c '
        set -euo pipefail
        config="$1"
        borgmatic="$2"
        passphrase_file="$3"
        test -s "$passphrase_file"
        export BORG_PASSPHRASE="$(< "$passphrase_file")"
        "$borgmatic" --config "$config" repo-info --verbosity -1 >/dev/null 2>&1 ||
          "$borgmatic" --config "$config" repo-create --encryption repokey --verbosity 1
        exec "$borgmatic" --config "$config" create prune compact --verbosity 1
      ' _ ${hotConfigPath name} ${pkgs.borgmatic}/bin/borgmatic ${hotSourcePassphrasePath}
    '';
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
            Environment = [
              "HOME=${homeDir}"
              "BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes"
            ];
          };
        })
      targets;

      systemd.user.timers = lib.mapAttrs' (name: target:
        lib.nameValuePair "home-emergency-backup-${name}" {
          Unit.Description = "Daily /home/mhugo emergency backup to ${name} (${target.schedule} with 30min jitter)";
          Timer = {
            OnCalendar = target.schedule;
            RandomizedDelaySec = "30min";
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

      xdg.configFile = lib.mapAttrs' (name: target:
        lib.nameValuePair "borgmatic.d/hot-source-${name}.yaml" {
          text = builtins.toJSON (hotSourceConfig name target);
        })
      targets;

      systemd.user.services = lib.mapAttrs' (name: target:
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
            RuntimeMaxSec = "60min";
            Nice = 19;
            IOSchedulingClass = "idle";
            CPUWeight = 10;
            IOWeight = 10;
            Environment = [
              "HOME=${homeDir}"
            ];
          };
        })
      targets;

      systemd.user.timers = {
        hot-source-hel1 = {
          Unit.Description = "Hot-source backup to HEL1 every 30 minutes";
          Timer = {
            OnCalendar = "*-*-* *:00/30:00";
            RandomizedDelaySec = "2min";
            Persistent = true;
            Unit = "hot-source-hel1.service";
          };
          Install.WantedBy = ["timers.target"];
        };
        hot-source-fsn1 = {
          Unit.Description = "Hot-source backup to FSN1 every 30 minutes, staggered by 15 minutes";
          Timer = {
            OnCalendar = "*-*-* *:15/30:00";
            RandomizedDelaySec = "2min";
            Persistent = true;
            Unit = "hot-source-fsn1.service";
          };
          Install.WantedBy = ["timers.target"];
        };
      };
    })
  ]
