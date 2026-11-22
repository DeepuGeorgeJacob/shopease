#!/usr/bin/env bash
# Print semantic-version bump candidates from the highest local stable tag.
# Usage: bash scripts/next-version.sh [--prefix v|none]
# Default: auto-detect the prefix used by existing tags (v when present).

set -euo pipefail

prefix_mode="auto"

die() {
  echo "ERROR: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      [[ $# -ge 2 ]] || die "--prefix needs a value (v or none)"
      prefix_mode="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: bash scripts/next-version.sh [--prefix v|none]"
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

case "$prefix_mode" in
  auto|v|none) ;;
  *) die "--prefix must be 'v' or 'none'" ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git repository"

tags="$(git tag --list)"

stable="$(printf '%s\n' "$tags" \
  | sed -n 's/^\(v\{0,1\}\)\([0-9][0-9]*\)\.\([0-9][0-9]*\)\.\([0-9][0-9]*\)$/\2 \3 \4 \1\2.\3.\4/p' \
  | sort -k1,1n -k2,2n -k3,3n \
  | tail -1)"

prefix="v"
if [[ -n "$stable" ]]; then
  read -r major minor patch latest <<< "$stable"
  major=$((10#$major))
  minor=$((10#$minor))
  patch=$((10#$patch))
  if [[ "$latest" != v* ]]; then
    prefix=""
  fi
  recommended="patch"
else
  major=0
  minor=0
  patch=0
  latest="none"
  recommended="minor"
fi

if [[ "$prefix_mode" == "v" ]]; then
  prefix="v"
elif [[ "$prefix_mode" == "none" ]]; then
  prefix=""
fi

patch_tag="${prefix}${major}.${minor}.$((patch + 1))"
minor_tag="${prefix}${major}.$((minor + 1)).0"
major_tag="${prefix}$((major + 1)).0.0"

echo "latest=$latest"
echo "prefix=${prefix:-none}"
echo "patch=$patch_tag"
echo "minor=$minor_tag"
echo "major=$major_tag"
echo "recommended=$recommended"
