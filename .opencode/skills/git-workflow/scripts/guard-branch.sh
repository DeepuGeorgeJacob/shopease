#!/usr/bin/env bash
# Fail when a commit or push would target a protected branch.
# Usage: guard-branch.sh [--target <branch-or-ref>]
set -euo pipefail

protected="${GIT_PROTECTED_BRANCHES:-main master}"
target=""

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      target="${2:-}"
      shift 2
      ;;
    *)
      echo "usage: $0 [--target <branch-or-ref>]" >&2
      exit 2
      ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not inside a git work tree; refusing to continue." >&2
  exit 1
fi

is_protected() {
  local branch="${1#refs/heads/}"
  local b
  for b in $protected; do
    if [ "$branch" = "$b" ]; then
      return 0
    fi
  done
  return 1
}

if [ -n "$target" ] && is_protected "$target"; then
  echo "ERROR: '$target' is a protected branch. Commits and pushes to it are blocked." >&2
  echo "Push a feature branch instead, then open a pull request." >&2
  exit 1
fi

current="$(git symbolic-ref --quiet --short HEAD || true)"

if [ -z "$current" ]; then
  echo "ok: detached HEAD (no protected branch is checked out)"
  exit 0
fi

if is_protected "$current"; then
  echo "ERROR: '$current' is a protected branch. Commits and pushes on '$current' are blocked." >&2
  echo "Create a feature branch first:" >&2
  echo "  git switch -c <type>/<slug> origin/$current" >&2
  exit 1
fi

echo "ok: on '$current' (not protected)"
