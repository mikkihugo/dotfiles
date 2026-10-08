# home/modules/git.nix — version control configuration
#
# Covers: git (identity, delta pager, aliases), jujutsu, GitHub CLI.
{pkgs, ...}: let
  # HTTPS credentials for Forgejo come from OpenBao at call time, never from a
  # git config file. Scoped to the one host, so no other remote is offered it.
  forgejoCredentialHelper = pkgs.writeShellScript "git-credential-forgejo-bao" ''
    export BAO_BIN=${pkgs.openbao}/bin/bao
    exec ${pkgs.bash}/bin/bash ${../../scripts/git-credential-forgejo-bao} "$@"
  '';
in {
  programs = {
    # git: canonical identity + delta diff pager + quality-of-life aliases.
    # delta replaces the default diff output with syntax-highlighted views.
    # navigate=true lets you jump between hunks with n/N in less.
    git = {
      enable = true;
      settings = {
        user = {
          name = "Mikael Hugo";
          email = "mikkihugo@users.noreply.github.com";
        };
        # /home/mhugo/code/flakecache is owned by root (nix build cache);
        # mark it safe so `git status` works inside it without sudo.
        safe.directory = "/home/mhugo/code/flakecache";
        init.defaultBranch = "main";
        pull.rebase = true;
        # Forgejo SSH is port 2222. Rewrite scp-style and portless ssh URLs so
        # Git dials that port even when it does not apply Host entries.
        url."ssh://git@git.centralcloud.net:2222/".insteadOf = [
          "git@git.centralcloud.net:"
          "ssh://git@git.centralcloud.net/"
        ];
        credential."https://git.centralcloud.net".helper = "!${forgejoCredentialHelper}";
        core.pager = "delta";
        interactive.diffFilter = "delta --color-only";
        delta = {
          navigate = true;
          light = false;
          syntax-theme = "Nord";
          line-numbers = true;
          side-by-side = false; # single-column is easier on narrow terminals
        };
        merge.conflictstyle = "diff3"; # shows base in conflicts — clearer resolution
        diff.colorMoved = "default";
        diff.sopsdiffer.textconv = "sops -d"; # `git diff` decrypts SOPS files
        alias = {
          s = "status -sb";
          a = "add";
          c = "commit";
          co = "checkout";
          b = "branch";
          p = "push";
          pl = "pull --rebase";
          f = "fetch --all --prune";
          lg = "log --oneline --graph --decorate";
          ll = "log --graph --pretty=format:'%C(yellow)%h%Creset -%C(auto)%d%Creset %s %C(green)(%cr) %C(bold blue)<%an>%Creset'";
          d = "diff";
          dc = "diff --cached";
          ds = "diff --stat";
          sl = "stash list";
          sa = "stash apply";
          sp = "stash pop";
          undo = "reset --soft HEAD~1";
          pushit = "!git push -u origin $(git branch --show-current)";
          rebase-main = "!git rebase -i $(git merge-base HEAD main)";
        };
      };
    };

    # jujutsu: primary VCS for jj-backed repos (git colocated backend).
    # Package is overlaid from nixpkgs-unstable (0.45.1) in flake.nix — 26.05
    # still ships 0.41. difft gives structural diffs instead of line noise.
    # 0.43 removed git_head()/git_refs() revset functions; do not reintroduce.
    jujutsu = {
      enable = true;
      settings = {
        user = {
          name = "Mikael Hugo";
          email = "mikkihugo@users.noreply.github.com";
        };
        ui = {
          pager = "less -FRX";
          default-command = "log"; # `jj` alone shows the commit graph
          diff-formatter = "difft";
        };
        "--scope" = [
          {
            "--when".repositories = [
              "/home/mhugo/code/singularity-engine"
              "/home/mhugo/code/worktrees/jj/singularity-engine"
              "/home/mhugo/code/jcode"
              "/home/mhugo/code/worktrees/jj/jcode"
              "/srv/infra"
              "/home/mhugo/code/worktrees/jj/infra"
              "/home/mhugo/.dotfiles"
            ];
            # Publication bookmark is main@origin in all four repositories.
            # Without this alias jj's trunk() falls back to root() and the
            # published main stays mutable.
            "revset-aliases"."trunk()" = "main@origin";
          }
        ];
      };
    };

    # gh: PR review and repo management.
    # ssh protocol avoids HTTPS credential prompts.
    gh = {
      enable = true;
      settings = {
        git_protocol = "ssh";
        prompt = "enabled";
        aliases = {
          co = "pr checkout";
        };
      };
    };
  };
}
