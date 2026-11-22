#!/usr/bin/env bash
# Read-only preflight inspector for the tag-push skill.
# Usage:
#   bash scripts/inspect-tag-repo.sh [--remote origin] [--base main] [--tag v1.2.3]
# Exits non-zero when the strict release gate fails.

set -euo pipefail

remote="origin"
base=""
tag=""

die() {
  echo "ERROR: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --remote)
      [[ $# -ge 2 ]] || die "--remote needs a value"
      remote="$2"
      shift 2
      ;;
    --base)
      [[ $# -ge 2 ]] || die "--base needs a value"
      base="$2"
      shift 2
      ;;
    --tag)
      [[ $# -ge 2 ]] || die "--tag needs a value"
      tag="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: bash scripts/inspect-tag-repo.sh [--remote origin] [--base main] [--tag v1.2.3]"
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repository"
git remote get-url "$remote" >/dev/null 2>&1 || die "remote '$remote' is not configured"

if [[ -z "$base" ]]; then
  base="$(git symbolic-ref --quiet --short "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
  base="${base#*/}"
  [[ -n "$base" ]] || base="main"
fi

base_ref="$remote/$base"
git show-ref --verify --quiet "refs/remotes/$base_ref" \
  || die "$base_ref is missing locally; run: git fetch $remote --prune --tags"

head_sha="$(git rev-parse HEAD)"
branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo '<detached HEAD>')"
status="$(git status --porcelain)"
ahead="$(git rev-list --count "$base_ref..HEAD")"
behind="$(git rev-list --count "HEAD..$base_ref")"

latest="$(git tag --list \
  | sed -n 's/^v\{0,1\}\([0-9][0-9]*\)\.\([0-9][0-9]*\)\.\([0-9][0-9]*\)$/\1.\2.\3/p' \
  | sort -t. -k1,1n -k2,2n -k3,3n \
  | tail -1)"

echo "Remote:            $remote ($(git remote get-url "$remote"))"
echo "Base:              $base_ref"
echo "Branch:            $branch"
echo "HEAD:              $(git rev-parse --short "$head_sha") $(git log -1 --format=%s "$head_sha")"
echo "HEAD sha:          $head_sha"
echo "Base tip:          $(git rev-parse --short "$base_ref")"
echo "Ahead/behind:      $ahead/$behind (base..HEAD / HEAD..base)"
echo "Worktree:          $([[ -n "$status" ]] && echo DIRTY || echo clean)"
if [[ -n "$status" ]]; then
  echo "$status" | sed 's/^/    /'
fi
echo "Latest stable tag: ${latest:-none}"

failures=""

if [[ -n "$status" ]]; then
  failures="$failures worktree-is-dirty;"
fi

if git merge-base --is-ancestor "$head_sha" "$base_ref" 2>/dev/null; then
  if [[ "$ahead" -ne 0 ]]; then
    failures="$failures head-not-on-base;"
  fi
else
  failures="$failures head-not-merged-into-$base;"
fi

if [[ -n "$tag" ]]; then
  local_exists="no"
  remote_exists="no"
  git show-ref --verify --quiet "refs/tags/$tag" && local_exists="yes"
  if git ls-remote --exit-code --tags "$remote" "refs/tags/$tag" >/dev/null 2>&1; then
    remote_exists="yes"
  fi
  echo "Tag:               $tag"
  echo "  local:           $local_exists"
  echo "  remote:          $remote_exists"
  [[ "$local_exists" == "no" ]] || failures="$failures tag-exists-locally;"
  [[ "$remote_exists" == "no" ]] || failures="$failures tag-exists-on-$remote;"
fi

if [[ -z "$failures" ]]; then
  echo "GATE: PASS"
  if [[ "$behind" -gt 0 ]]; then
    echo "NOTE: HEAD is $behind commit(s) behind $base_ref - confirm this is the commit to release."
  fi
  exit 0
fi

echo "GATE: FAIL:$failures" >&2
exit 1
