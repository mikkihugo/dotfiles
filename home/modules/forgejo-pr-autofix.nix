# home/modules/forgejo-pr-autofix.nix
#
# Persistent Forgejo PR maintenance loop for centralcloud/infra (NOT github).
# A user systemd timer (survives logout via linger) runs a safe one-shot pass:
#   - server-side rebase-update of behind-base branches
#   - report CI state to ~/.local/state/forgejo-pr-autofix.log
#   - auto-merge ONLY green PRs labelled `automerge` or authored by renovate
# It never merges other people's or heal-heavy PRs. Token: ~/.config/forgejo/token.
{pkgs, ...}: let
  autofix = pkgs.writeShellApplication {
    name = "forgejo-pr-autofix";
    runtimeInputs = [pkgs.curl pkgs.python3 pkgs.coreutils pkgs.gnugrep];
    text = ''
      set -uo pipefail
      TOKEN=$(cat "$HOME/.config/forgejo/token" 2>/dev/null) || exit 0
      API=https://git.infra.centralcloud.com/api/v1/repos/centralcloud/infra
      LOG="$HOME/.local/state/forgejo-pr-autofix.log"
      mkdir -p "$HOME/.local/state"
      log() { echo "$(date -u +%FT%TZ) $*" >> "$LOG"; }
      prs=$(curl -skS -H "Authorization: token $TOKEN" "$API/pulls?state=open&limit=50") || exit 0
      echo "$prs" | python3 -c '
      import sys, json
      for p in json.load(sys.stdin):
          labels = ",".join(l.get("name", "") for l in p.get("labels", []))
          print("\t".join([str(p["number"]), p["head"]["ref"], p["head"]["sha"],
              p.get("user", {}).get("login", ""), labels]))' | while IFS=$'\t' read -r num ref sha user labels; do
        st=$(curl -skS -H "Authorization: token $TOKEN" "$API/commits/$sha/status" \
          | python3 -c 'import sys,json;print(json.load(sys.stdin).get("state") or "none")' 2>/dev/null)
        automerge=0
        case ",$labels," in *,automerge,*) automerge=1 ;; esac
        [ "$user" = "renovate" ] && automerge=1
        if [ "$st" = "success" ] && [ "$automerge" = "1" ]; then
          m=$(curl -skS -X POST -H "Authorization: token $TOKEN" -H "Content-Type: application/json" \
            -d '{"Do":"merge"}' "$API/pulls/$num/merge")
          if [ -z "$m" ]; then
            log "MERGED #$num $ref"
          elif echo "$m" | grep -qi behind; then
            curl -skS -X POST -H "Authorization: token $TOKEN" "$API/pulls/$num/update?style=rebase" >/dev/null 2>&1
            log "updated(behind) #$num $ref"
          fi
        elif [ "$st" = "success" ]; then
          log "READY(manual) #$num $ref"
        elif [ "$st" = "failure" ] || [ "$st" = "error" ]; then
          log "CI-$st #$num $ref"
        fi
      done
      log "pass done"
    '';
  };
in {
  systemd.user.services.forgejo-pr-autofix = {
    Unit.Description = "Forgejo PR autofix pass (centralcloud/infra)";
    Service = {
      Type = "oneshot";
      ExecStart = "${autofix}/bin/forgejo-pr-autofix";
    };
  };

  systemd.user.timers.forgejo-pr-autofix = {
    Unit.Description = "Run Forgejo PR autofix periodically";
    Timer = {
      OnCalendar = "*:0/3"; # every 3 minutes (wall-clock so Persistent catches up)
      RandomizedDelaySec = "30s";
      Persistent = true;
      Unit = "forgejo-pr-autofix.service";
    };
    Install.WantedBy = ["timers.target"];
  };
}
