#!/usr/bin/env bash
# Verify a locally created, remote-pushed release tag.
# Usage: bash scripts/verify-tag.sh <tag> [remote]

set -euo pipefail

tag="${1:-}"
remote="${2:-origin}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -n "$tag" ]] || fail "usage: verify-tag.sh <tag> [remote]"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "not a git repository"
git remote get-url "$remote" >/dev/null 2>&1 || fail "remote '$remote' is not configured"

tag_type="$(git cat-file -t "refs/tags/$tag" 2>/dev/null || true)"
[[ "$tag_type" == "tag" ]] || fail "local '$tag' is not an annotated tag (found: ${tag_type:-missing})"

tag_commit="$(git rev-parse -q --verify "refs/tags/${tag}^{commit}")" \
  || fail "cannot resolve '$tag' to a commit"
head_commit="$(git rev-parse HEAD)"
[[ "$tag_commit" == "$head_commit" ]] \
  || fail "tag points at $tag_commit while HEAD is $head_commit"

remote_output="$(git ls-remote --tags "$remote" "refs/tags/$tag" "refs/tags/${tag}^{}" 2>/dev/null || true)"
[[ -n "$remote_output" ]] || fail "tag '$tag' was not found on remote '$remote'"

remote_commit="$(printf '%s\n' "$remote_output" | awk -v ref="refs/tags/${tag}^{}" '$2 == ref {print $1; exit}')"
if [[ -z "$remote_commit" ]]; then
  remote_commit="$(printf '%s\n' "$remote_output" | awk -v ref="refs/tags/$tag" '$2 == ref {print $1; exit}')"
fi
[[ -n "$remote_commit" ]] || fail "cannot determine remote tag commit for '$tag'"
[[ "$remote_commit" == "$tag_commit" ]] \
  || fail "remote tag points at $remote_commit while local tag points at $tag_commit"

[[ -z "$(git status --porcelain)" ]] || fail "worktree became dirty during tagging"

echo "PASS: annotated tag $tag -> $(git rev-parse --short "$tag_commit") exists on $remote and matches HEAD"
