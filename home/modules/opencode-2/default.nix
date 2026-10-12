# home/modules/opencode-2/default.nix — OpenCode 2.x derivation
#
# Lineage: this is the package derivation from nixpkgs PR #572946
# (`opencode_2: init at 2.0.26`) by GaetanLepage, with three SHA/version
# literals substituted to build 2.0.27 from upstream's git tag `v2.0.27`
# (the latest release at the time this file was forked; PR #572946
# has not been refreshed upstream).
#
# Upstream PR: https://github.com/NixOS/nixpkgs/pull/572946
# Upstream PR head SHA: 25b2488a28c7778eb8f89bfec43442f3729ad7bb
#   (file: pkgs/by-name/op/opencode_2/package.nix)
# nixos-26.05 / unstable / master do not carry OpenCode 2.x; we maintain
# this file in-tree until upstream merges.
#
# Three substituted literals (verified by build attempt 2026-10-12):
#   - version:           2.0.26  -> 2.0.27
#   - src.hash:          sha256-umhEz5um90EiBHvVZzQw+HoBFO088ZI1g7Ost9BUxhM=
#                       -> sha256-C+MOdj8CPcP6cLWJl/KBg8/oR/XVOkn0+d7/54YKuU4=
#                       (NAR hash of the unpacked upstream v2.0.27 git tree)
#   - node_modules.outputHash:
#                       sha256-wR7VMRcHOcj3hdGdtMoHAgbwNsLsNscHNaCUwKjwr4o=
#                       -> sha256-JT4BlVDqKwf1mhs89vXIUyb0NZIT4feNE3rNWsozbCM=
#                       (NAR hash of `bun install --frozen-lockfile
#                        --filter ./packages/cli --filter ./packages/app`
#                        on the v2.0.27 lockfile)
#
# Maintenance: when the upstream PR is refreshed to a newer 2.x release
# (or when nixos-unstable / master finally carries OpenCode 2.x),
# delete this file, drop the `nixpkgs-oc2` flake input from flake.nix
# (if any), and switch the wrapper in `home/modules/ai-tools.nix` to
# `exec "$HOME/.nix-profile/bin/opencode"` over `pkgs.opencode`. Until
# then, this is the canonical source of truth for OpenCode 2.x on this
# devbox.
{
  lib,
  stdenv,
  bun,
  darwin,
  fetchFromGitHub,
  makeBinaryWrapper,
  nodejs,
  nix-update-script,
  ripgrep,
  sysctl,
  wayland,
  installShellFiles,
  versionCheckHook,
  writableTmpDirAsHomeHook,
}:
let
  node_modules =
    finalAttrs:
    stdenv.mkDerivation {
      pname = "${finalAttrs.pname}-node_modules";
      inherit (finalAttrs) version src;

      __structuredAttrs = true;
      strictDeps = true;

      impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
        "GIT_PROXY_COMMAND"
        "SOCKS_SERVER"
      ];

      nativeBuildInputs = [
        bun
        writableTmpDirAsHomeHook
      ];

      dontConfigure = true;

      buildPhase = ''
        runHook preBuild

        export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
        bun install \
          --cpu="*" \
          --frozen-lockfile \
          --filter ./ \
          --filter ./packages/app \
          --filter ./packages/cli \
          --ignore-scripts \
          --no-progress \
          --os="*"

        bun --bun ./nix/scripts/canonicalize-node-modules.ts
        bun --bun ./nix/scripts/normalize-bun-binaries.ts

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p $out
        find . -type d -name node_modules -exec cp -R --parents {} $out \;

        # opencode targets only Linux and Darwin (see meta.platforms), so the
        # Windows executables that "bun install --os=*" fetches are never
        # executed. Dropping them keeps the output reproducible on hosts whose
        # security endpoint agents scan the store, and removes the vulnerable
        # bundled 7za.exe that will be quarantined.
        find $out -type f -name '*.exe' -delete

        runHook postInstall
      '';

      # NOTE: Required else we get errors that our fixed-output derivation references store paths
      dontFixup = true;

      outputHash = "sha256-JT4BlVDqKwf1mhs89vXIUyb0NZIT4feNE3rNWsozbCM=";
      outputHashAlgo = "sha256";
      outputHashMode = "recursive";
    };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "opencode";
  version = "2.0.27";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "anomalyco";
    repo = "opencode";
    tag = "v${finalAttrs.version}";
    hash = "sha256-C+MOdj8CPcP6cLWJl/KBg8/oR/XVOkn0+d7/54YKuU4=";
  };

  postPatch =
    # Relax Bun version check to be a warning instead of an error
    ''
      substituteInPlace packages/script/src/index.ts \
        --replace-fail \
        'throw new Error(`This script requires bun@''${expectedBunVersionRange}' \
        'console.warn(`Warning: This script requires bun@''${expectedBunVersionRange}'
    '';

  nativeBuildInputs = [
    bun
    nodejs
    installShellFiles
    makeBinaryWrapper
    writableTmpDirAsHomeHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    darwin.sigtool
  ];

  configurePhase = ''
    runHook preConfigure

    cp -R ${finalAttrs.passthru.node_modules}/. .
    patchShebangs node_modules
    patchShebangs packages/*/node_modules

    runHook postConfigure
  '';

  env = {
    OPENCODE_DISABLE_MODELS_FETCH = true;
    OPENCODE_VERSION = finalAttrs.version;
    OPENCODE_CHANNEL = "prod";
    NODE_OPTIONS = "--max-old-space-size=4096";
  };

  buildPhase = ''
    runHook preBuild

    cd ./packages/cli
    bun --bun ./script/build.ts --single --skip-install
    bun --bun ./script/schema.ts config.json

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 dist/cli-*/bin/opencode $out/bin/opencode
    wrapProgram $out/bin/opencode \
      --set OPENCODE_DISABLE_AUTOUPDATE true \
      --prefix PATH : ${
        lib.makeBinPath (
          [
            ripgrep
          ]
          # bun runs sysctl to detect if running on rosetta2
          ++ lib.optionals stdenv.hostPlatform.isDarwin [
            sysctl
          ]
        )
      } ${
        # OpenTUI dlopens Wayland for clipboard images
        lib.optionalString stdenv.hostPlatform.isLinux ''
          --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ wayland ]}
        ''
      }

    # Upstream ships `opencode2` as an alias of `opencode`
    ln -s opencode $out/bin/opencode2

    install -Dm644 config.json $out/share/config.json

    runHook postInstall
  '';

  postInstall =
    lib.optionalString stdenv.hostPlatform.isDarwin ''
      codesign --force --sign - $out/bin/.opencode-wrapped
    ''
    + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
      for shell in bash fish zsh; do
        $out/bin/opencode --completions $shell > opencode.$shell
        substitute opencode.$shell opencode2.$shell --replace-fail opencode opencode2
      done

      installShellCompletion --cmd opencode \
        --bash opencode.bash \
        --fish opencode.fish \
        --zsh opencode.zsh

      installShellCompletion --cmd opencode2 \
        --bash opencode2.bash \
        --fish opencode2.fish \
        --zsh opencode2.zsh
    '';

  dontStrip = true;

  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  doInstallCheck = true;
  versionCheckKeepEnvironment = [
    "HOME"
    "OPENCODE_DISABLE_MODELS_FETCH"
  ];

  passthru = {
    jsonschema = {
      config = "${finalAttrs.finalPackage}/share/config.json";
    };
    node_modules = node_modules finalAttrs;
    updateScript = nix-update-script {
      extraArgs = [
        "--subpackage"
        "node_modules"
        "--version-regex"
        "^v(2\\..*)$"
      ];
    };
  };

  meta = {
    description = "AI coding agent built for the terminal";
    homepage = "https://github.com/anomalyco/opencode";
    changelog = "https://github.com/anomalyco/opencode/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      delafthi
      DuskyElf
      graham33
    ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "opencode";
  };
})
