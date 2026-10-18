# Per-user coordination daemon for the Engine repo facade.
#
# Purpose: keep one warm coordination inbox/cache for every principal on the
# devbox. The daemon is deliberately identity-neutral: SE_SWARM_IDENTITY is
# not set here, so the existing repo coord clients remain responsible for
# principal selection.
#
# Evidence: after activation, repo-coord.service must be active and
# %t/repo-coord/coord.sock must be owner-only; repo coord poll/status should
# report the daemon route ("coord: via daemon ...") when a client uses it.
# Falsifier: an inactive unit, missing socket, or client output without the
# daemon-route trace.
{
  lib,
  hostname ? "",
  ...
}:
lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
  systemd.user.services.repo-coord = {
    Unit = {
      Description = "Per-user repo coordination daemon";
      Documentation = "https://git.centralcloud.net/singularity/singularity-engine";
      After = ["default.target"];
    };

    Service = {
      Type = "simple";
      WorkingDirectory = "/home/mhugo/code/singularity-engine";
      # direnv supplies the admitted Engine environment and selects the
      # shared repo-vcs generation; the executable remains the canonical
      # generated facade, never a task-workspace build.
      ExecStart = "/home/mhugo/.nix-profile/bin/direnv exec /home/mhugo/code/singularity-engine /home/mhugo/code/singularity-engine/bin/repo coord serve";
      Restart = "on-failure";
      RestartSec = 5;
      Environment = [
        "SE_COORD_SOCKET=%t/repo-coord/coord.sock"
      ];
    };

    Install = {
      WantedBy = ["default.target"];
    };
  };
}
