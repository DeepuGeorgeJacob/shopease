#!/usr/bin/env bash
# Install the pre-commit and pre-push guards into this clone's .git/hooks.
set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not inside a git work tree." >&2
  exit 1
fi

root="$(git rev-parse --show-toplevel)"
cd "$root"

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hooks_src="$(cd "$scripts_dir/../hooks" && pwd)"
hooks_dir="$(git rev-parse --git-path hooks)"
mkdir -p "$hooks_dir"

for hook in pre-commit pre-push; do
  src="$hooks_src/$hook"
  dest="$hooks_dir/$hook"

  if [ ! -f "$src" ]; then
    echo "ERROR: missing hook source: $src" >&2
    exit 1
  fi

  if [ -f "$dest" ] && ! cmp -s "$src" "$dest"; then
    backup="$dest.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$dest" "$backup"
    echo "backed up existing $hook to $backup"
  fi

  cp "$src" "$dest"
  chmod +x "$dest"
  echo "installed $dest"
done

echo "Protected branches: ${GIT_PROTECTED_BRANCHES:-main master}"
