# Tabby local sessions use the standard xterm-256color terminal contract.
# Keep its config declarative so TUIs see the same capability identity as they
# do in the existing managed shell and WezTerm paths.
{pkgs, ...}: {
  home.packages = [pkgs.tabby];

  home.file.".config/tabby/config.yaml" = {
    source = ../../config/tabby/config.yaml;
    force = true;
  };
}
