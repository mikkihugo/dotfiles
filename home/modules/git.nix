# home/modules/git.nix — version control configuration
#
# Covers: git (identity, delta pager, aliases), jujutsu, GitHub CLI.
{_}: {
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

    # jujutsu: primary VCS for the ace-coder project (git backend).
    # difft gives structural diffs instead of line-by-line noise.
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
