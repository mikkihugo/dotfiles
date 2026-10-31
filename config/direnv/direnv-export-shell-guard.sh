# Purpose: reject bare `direnv export` with AIP-193-style actionable fields.
# Consumer: config/direnv/direnv-export-shell-guard.nix (direnv CLI wrapper).
# Failure boundary: operators and agents mistype export without a shell name.
# Falsifier: `direnv export` still reaches upstream with an empty shell target.

# Returns 0 to delegate to real direnv; prints to stderr and returns 3 on violation
# (google.rpc.Code.INVALID_ARGUMENT).
direnv_export_shell_guard() {
	[[ "${1-}" == export ]] || return 0
	[[ -n "${2-}" ]] || {
		direnv_export_shell_guard_msg >&2
		return 3
	}
	return 0
}

direnv_export_shell_guard_msg() {
	cat <<'EOF'
direnv: code=INVALID_ARGUMENT reason=EXPORT_SHELL_REQUIRED domain=direnv.centralcloud.net/cli
message: direnv export requires a target shell (bash, zsh, fish, …). Bare 'direnv export' is invalid outside a shell hook that supplies the target.
help(eval_zsh): eval "$(direnv export zsh)"
help(eval_bash): eval "$(direnv export bash)"   # bin/repo recovery and agent shells
help(interactive): direnv allow && cd .        # reload after .envrc or allow changes
help(more): https://google.aip.dev/193
EOF
}
