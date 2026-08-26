{
  hostname ? "",
  lib,
  ...
}:
lib.mkIf (lib.toLower hostname == "cc-se-sto-devbox-01") {
  # Fleet hosts run system sccache.service (nix-cache.nix): one daemon, one L0
  # disk cache (/var/cache/sccache), one FlakeCache /host bucket. Point every
  # client at the system socket so jcode, engine, and CI runner jobs share hits.
  home.sessionVariables = {
    SCCACHE_DIR = lib.mkForce "/var/cache/sccache";
    SCCACHE_SERVER_UDS = lib.mkForce "/run/sccache/server.sock";
    SCCACHE_CACHE_SIZE = lib.mkForce "8G";
    SCCACHE_IDLE_TIMEOUT = lib.mkForce "0";
    SCCACHE_IGNORE_SERVER_IO_ERROR = lib.mkForce "1";
  };
}
