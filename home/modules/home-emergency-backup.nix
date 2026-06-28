{
  lib,
  pkgs,
  hostname ? "",
  ...
}: let
  shortHost =
    if hostname != ""
    then hostname
    else "mhugo";
  homeDir = "/home/mhugo";
  keyPath = "${homeDir}/.ssh/storagebox-backup";
  sshCommand = "${pkgs.openssh}/bin/ssh -i ${keyPath} -p 23 -o BatchMode=yes -o StrictHostKeyChecking=yes";
  commonConfig = {
    source_directories = [homeDir];
    exclude_patterns = [
      "${homeDir}/.cache"
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
      "${homeDir}/**/.gradle/caches"
      "${homeDir}/**/.m2/repository"
      "${homeDir}/**/coverage"
      "${homeDir}/**/result"
      "${homeDir}/**/result-*"
      "${homeDir}/.antigravity-ide-server/data/logs"
    ];
    exclude_if_present = [".nobackup"];
    bootstrap.store_config_files = false;
    ssh_command = sshCommand;
    compression = "none";
    extra_borg_options.create = "--upload-buffer 1024 --upload-ratelimit 0";
    borg_exit_codes = [
      {
        code = 105;
        treat_as = "warning";
      }
    ];
    keep_hourly = 24;
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
      onBootSec = "5min";
      path = "ssh://u579183-sub5@u579183-sub5.your-storagebox.de:23/./borg/${shortHost}";
    };
    fsn1 = {
      description = "FSN1";
      onBootSec = "35min";
      path = "ssh://u602823-sub5@u602823-sub5.your-storagebox.de:23/./borg/${shortHost}";
    };
  };
  borgmaticConfig = name: target:
    commonConfig
    // {
      repositories = [
        {
          path = target.path;
          label = "storagebox-${name}";
        }
      ];
      archive_name_format = "{hostname}-${name}-{now:%Y-%m-%dT%H:%M:%SZ}";
    };
  configPath = name: "${homeDir}/.config/borgmatic.d/home-emergency-${name}.yaml";
  restoreKeyPackage = pkgs.writeShellScriptBin "storagebox-backup-key-restore" ''
    set -euo pipefail

    export HOME="${homeDir}"
    export BAO_ADDR="''${BAO_ADDR:-https://kv.infra.centralcloud.com}"

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
in {
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
      };
      Service = {
        Type = "oneshot";
        ExecStartPre = "${restoreKeyPackage}/bin/storagebox-backup-key-restore";
        ExecStart = "${pkgs.borgmatic}/bin/borgmatic --config ${configPath name} --verbosity 1";
        Environment = [
          "HOME=${homeDir}"
          "BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes"
        ];
      };
    })
  targets;

  systemd.user.timers = lib.mapAttrs' (name: target:
    lib.nameValuePair "home-emergency-backup-${name}" {
      Unit.Description = "Hourly /home/mhugo emergency backup to ${name}";
      Timer = {
        OnBootSec = target.onBootSec;
        OnUnitActiveSec = "1h";
        Persistent = true;
        Unit = "home-emergency-backup-${name}.service";
      };
      Install.WantedBy = ["timers.target"];
    })
  targets;
}
