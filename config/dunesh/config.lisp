;; Dune Shell Configuration
;; ~/.dotfiles/config/dunesh/config.lisp

;; Load at startup
(println "🏖️  Welcome to Dune Shell - A shell by the beach!")
(println "   Type (help) for documentation")
(println "   Type (exit) to quit")

;; Environment setup
(setenv "EDITOR" "hx")
(setenv "VISUAL" "hx")
(setenv "PAGER" "bat")
(setenv "BAT_THEME" "OneHalfDark")

;; Path additions
(let ((paths '("~/.local/bin"
               "~/.dotfiles/.scripts"
               "~/.cargo/bin"
               "~/go/bin")))
  (for path paths
    (setenv "PATH" (str (expand path) ":" (env "PATH")))))

;; Aliases using Dune's macro system
(macro alias (name command)
  `(fn ,name (&rest args)
     (if args
       (run ,command @args)
       (run ,command))))

;; Modern tool aliases
(alias ls "eza")
(alias ll "eza -la --git --time-style=relative")
(alias la "eza -a")
(alias l "eza -l --git")
(alias tree "eza --tree")
(alias cat "bat --paging=never")
(alias grep "rg")
(alias find "fd --threads=4")
(alias ps "procs")
(alias du "dust")
(alias df "duf")
(alias top "btop")

;; Navigation aliases
(fn .. () (cd ".."))
(fn ... () (cd "../.."))
(fn .... () (cd "../../.."))
(fn c (&optional pattern)
  (if pattern
    (let ((matches (split "\n" (read (| (fd "-t" "d" "-d" "1" 
                                            (str "*" pattern "*") 
                                            "~/code" 
                                            "--base-directory" "~/code"))))))
      (case (len matches)
        0 (println (str "No repos matching '" pattern "'"))
        1 (cd (str "~/code/" (first matches)))
        _ (let ((selected (first (split "\n" 
                                       (read (| (echo (join "\n" matches))
                                               (fzf "--reverse" "--height=40%" 
                                                   (str "--prompt=Multiple matches for '" 
                                                        pattern "': "))))))))
            (when selected
              (cd (str "~/code/" selected))))))
    (cd "~/code")))

;; Git shortcuts
(alias g "git")
(alias gs "git status")
(alias ga "git add")
(alias gc "git commit")
(alias gp "git push")
(alias gl "git pull")
(alias gd "git diff")
(alias gco "git checkout")
(alias gb "git branch")

;; Docker shortcuts
(alias d "docker")
(alias dc "docker-compose")
(alias dps "docker ps")

;; Kubernetes shortcuts
(alias k "kubectl")
(alias kgp "kubectl get pods")
(alias kgs "kubectl get services")

;; Shell switching
(fn sh-switch () (run "~/.dotfiles/.scripts/shell-switcher.sh"))
(fn sh-bash () (exec "bash" "--login"))
(fn sh-zsh () (exec "zsh"))
(fn sh-nu () (exec "nu"))

;; Claude safety wrappers
(fn claude-shell () (run "~/.dotfiles/.scripts/claude-shell.sh"))
(fn safe-run (&rest args) 
  (run "~/.dotfiles/.scripts/claude-safe-wrapper.sh" @args))

;; Prompt customization
(set-prompt 
  (fn () 
    (str "🏖️  " (basename (pwd)) " ❯ ")))

;; Enhanced cd with auto-ls
(let ((original-cd cd))
  (fn cd (path)
    (original-cd path)
    (when (< (len (ls)) 20)
      (ll))))

;; Quick directory jumper
(fn z (&rest args)
  (if (run? "zoxide")
    (cd (read (| (zoxide "query" @args))))
    (println "zoxide not installed")))

;; Toolchain binaries are expected on PATH (Nix dev shell, etc.)

;; Help function
(fn help ()
  (println "
Dune Shell Quick Reference:
  
  Navigation:
    (c)           - cd to ~/code
    (c 'pattern') - cd to repo matching pattern
    (..)          - go up one directory
    (z 'query')   - smart cd with zoxide
  
  Git:
    (gs)  - git status
    (ga)  - git add
    (gc)  - git commit
    (gp)  - git push
  
  Shell Management:
    (sh-switch)     - interactive shell switcher
    (claude-shell)  - resource-limited shell
    (safe-run cmd)  - run command with limits
  
  Dune Specific:
    (help)         - this help
    (exit)         - exit shell
    (pwd)          - current directory
    (env)          - environment variables
    (run cmd args) - run external command
"))
