#!/usr/bin/env bash
# Current git branch + dirty/clean indicator for the pane's working directory.
# Output: " branch" (clean) | " branch●" (dirty) | "" (not a repo)
#
# Argument $1 = working directory (pass `#{pane_current_path}` from tmux).
# Reference: Tokyo Night's git-status.sh (behavior only — code is fresh).

dir="${1:-$PWD}"
cd "$dir" 2>/dev/null || exit 0

# Quickly bail if not inside a git work tree.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "?")

# Dirty detection — any unstaged, staged, or untracked files
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  printf ' %s●' "$branch"
else
  printf ' %s' "$branch"
fi
