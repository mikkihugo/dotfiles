# `pkgs.tabby` is TabbyML's server-side coding assistant, not the Eugeny/Tabby
# terminal emulator. Package the upstream, hash-pinned terminal AppImage so
# Home Manager owns the client without introducing an unrelated server.
{pkgs, ...}: {
  home.packages = [
    (pkgs.appimageTools.wrapType2 {
      pname = "tabby-terminal";
      version = "1.0.235";
      src = pkgs.fetchurl {
        url = "https://github.com/Eugeny/tabby/releases/download/v1.0.235/tabby-1.0.235-linux-x64.AppImage";
        hash = "sha256-DKXcAV/l7nhA8rIGhkzDfFL3w2t6c06GU6Oa6KV23O8="; # pragma: allowlist secret
      };
    })
  ];

  home.file.".config/tabby/config.yaml" = {
    source = ../../config/tabby/config.yaml;
    force = true;
  };
}
