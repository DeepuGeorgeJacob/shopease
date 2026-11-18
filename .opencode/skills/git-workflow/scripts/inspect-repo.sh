#!/usr/bin/env bash
# Read-only repository inspector used by the git-workflow skill.
# Usage: bash scripts/inspect-repo.sh [remote]
set -euo pipefail

remote="${1:-origin}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: not inside a git work tree" >&2
  exit 1
fi

root="$(git rev-parse --show-toplevel)"
cd "$root"

if ! git remote get-url "$remote" >/dev/null 2>&1; then
  echo "error: remote '$remote' does not exist" >&2
  exit 1
fi

base_ref=""
if git symbolic-ref -q "refs/remotes/$remote/HEAD" >/dev/null 2>&1; then
  base_ref="$(git symbolic-ref --short "refs/remotes/$remote/HEAD")"
elif git show-ref --verify --quiet "refs/remotes/$remote/main"; then
  base_ref="$remote/main"
elif git show-ref --verify --quiet "refs/remotes/$remote/master"; then
  base_ref="$remote/master"
fi

current="$(git branch --show-current || true)"
protected="${GIT_PROTECTED_BRANCHES:-main master}"
is_protected="no"
for b in $protected; do
  if [ -n "$current" ] && [ "$current" = "$b" ]; then
    is_protected="yes"
  fi
done

echo "repo_root: $root"
echo "remote_url: $(git remote get-url "$remote")"
echo "base_ref: ${base_ref:-<unknown>}"
echo "current_branch: ${current:-<detached HEAD>}"
echo "current_branch_protected: $is_protected"

if [ -n "$base_ref" ]; then
  echo "commits_ahead_of_base: $(git rev-list --count "$base_ref"..HEAD 2>/dev/null || echo 0)"
  echo "commits_behind_base: $(git rev-list --count HEAD.."$base_ref" 2>/dev/null || echo 0)"
fi

echo "working_tree_status:"
git status --porcelain=v1 | sed 's/^/  /' || true

echo "staged_diff_stat:"
git diff --cached --stat | sed 's/^/  /' || true

echo "unstaged_diff_stat:"
git diff --stat | sed 's/^/  /' || true

echo "untracked_files:"
git ls-files --others --exclude-standard | sed 's/^/  /' || true

echo "recent_commits:"
git log --oneline -5 | sed 's/^/  /' || true
