# Thin activation shim — delegates all worker configuration to the pinned
# ace-coder flake input so worker builds are cacheable and reproducible.
{pkgs, ace-coder, ...}: let
  ace-pkgs = ace-coder.packages.${pkgs.stdenv.hostPlatform.system};
in {
  imports = [
    ace-coder.homeManagerModules.ace-local-gpu-workers
  ];

  services.ace-local-gpu-workers = {
    enable = true;
    package = ace-pkgs.llm-gateway-workers-cuda-static;
    environmentFile = "/home/mhugo/.config/ace-coder/worker.env";
  };
}
