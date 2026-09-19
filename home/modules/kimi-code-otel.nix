# home/modules/kimi-code-otel.nix — kimi-code per-user OTel shell env bridge
#
# Operator-owned OTel defaults (`OTEL_EXPORTER_OTLP_ENDPOINT`,
# `OTEL_SERVICE_NAME`, `OTEL_TRACES_EXPORTER`, base `OTEL_RESOURCE_ATTRIBUTES`,
# `OTEL_PROPAGATORS`, `OTEL_BSP_*`) live in `/srv/infra/clusters/default/
# observability/otel-ingest.yaml` plus the host-rendered `/etc/otel/
# defaults.env` (`hosts/_shared/otel-defaults.nix`, imported by every
# managed NixOS host). That contract belongs to the operator tier, not to a
# per-user home-manager module.
#
# What THIS module owns: the shell-sourced env bridge
# (`~/.config/kimi-code/init-otel.sh`). It sources the operator-rendered
# `/etc/otel/defaults.env` so a kimi-code launched outside systemd still
# inherits the defaults, and surfaces a one-shot warning when the file is
# missing so the gap is observable.
#
# The session-scoped SessionStart hook (`~/.kimi-code/hooks/
# otel-resource-attrs.sh`) is NOT installed here: agent hooks are per-CLI
# files outside .dotfiles (see AGENTS.md "Agent hooks — not managed here").
_: {
  home.file.".config/kimi-code/init-otel.sh" = {
    source = ../../config/kimi-code/init-otel.sh;
    executable = false;
    force = true;
  };
}
