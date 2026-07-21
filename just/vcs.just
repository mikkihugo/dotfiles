set working-directory := ".."
set positional-arguments

runner := source_directory() + "/../scripts/repo-vcs.sh"

default:
    @just --list vcs

status:
    @{{runner}} status

diff *ARGS:
    @{{runner}} diff "$@"

log *ARGS:
    @{{runner}} log "$@"

show REVISION:
    @{{runner}} show "$1"

worktree-list:
    @{{runner}} worktree-list

fetch:
    @{{runner}} fetch

rebase REVISION:
    @{{runner}} rebase "$1"

describe MESSAGE:
    @{{runner}} describe "$1"

push BRANCH="main":
    @{{runner}} push "$1"

push-github BRANCH="main":
    @{{runner}} push-github "$1"

worktree-create NAME REVISION="main":
    @{{runner}} worktree-create "$1" "$2"

worktree-drop NAME:
    @{{runner}} worktree-drop "$1"

worktree-abandon NAME CONFIRMATION:
    @{{runner}} worktree-abandon "$1" "$2"

test:
    @{{runner}} contract-test
