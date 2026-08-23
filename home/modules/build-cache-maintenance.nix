{lib, ...}: {
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

  home.activation.retireLegacyUserSccache = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if systemctl --user is-active --quiet sccache.service 2>/dev/null; then
      systemctl --user stop sccache.service >/dev/null 2>&1 || true
      systemctl --user disable sccache.service >/dev/null 2>&1 || true
    fi
    # Deliberately NOT removing $HOME/.cache/sccache. It looked like a leftover
    # of the retired user unit, but it is live: 800M+ with a server.sock that
    # multiple running sccache daemons are listening on. home.sessionVariables
    # only reaches login shells and the systemd user environment, so anything
    # started without it -- agent `bash -lc` jobs, non-login ssh, containers --
    # falls back to sccache's default SCCACHE_DIR and daemonises there. An
    # unguarded rm -rf here therefore deleted a live cache out from under
    # running compilers on every activation, and it simply regrew.
    #
    # The real fix is to make SCCACHE_SERVER_UDS reach non-login environments so
    # those processes join the shared daemon instead of starting their own.
    # Until then, leaving the directory alone is strictly safer than wiping it.
  '';
}
