# Release tag versioning

Rules used by the `tag-push` skill. Follow these unless the user explicitly
chooses something else.

## Tag format

- Semantic version: `MAJOR.MINOR.PATCH`, for example `1.2.3`.
- Optional `v` prefix: use it when the highest existing stable tag uses it.
  A repository with no tags defaults to `v`.
- Prerelease/build suffixes such as `v1.2.3-rc.1` or `+build.5` are valid
  semver, but the auto-suggestion only considers stable `MAJOR.MINOR.PATCH`
  tags. Accept a suffix only when the user explicitly supplies it.
- Tag names are immutable. Never reuse, move, or delete a published tag as
  part of this workflow.

## Bump rules

Given the highest stable tag `MAJOR.MINOR.PATCH`:

| Bump    | Result                     | When to prefer it                          |
| ------- | -------------------------- | ------------------------------------------ |
| `patch` | `MAJOR.MINOR.(PATCH + 1)`  | Bug fixes, small corrections (default)     |
| `minor` | `MAJOR.(MINOR + 1).0`      | Backwards-compatible features              |
| `major` | `(MAJOR + 1).0.0`          | Breaking changes                           |

When the repository has no stable tags, the baseline is `0.0.0`, so the
candidates are `0.0.1` (patch), `0.1.0` (minor), and `1.0.0` (major). The skill
recommends `0.1.0` as a first release; the user may choose `1.0.0` instead.

## Choosing the bump

1. Run `bash scripts/next-version.sh` in the skill directory.
2. Use the `recommended` value as the first option in the question to the user.
3. Include the other bump options with their exact tag names.
4. Let the user type an exact tag name if none of the candidates fit.
5. Validate the final name against `^v?[0-9]+\.[0-9]+\.[0-9]+$` (with the `v`
   only when the repository convention uses it). Ask again when invalid.

## Examples

- Highest tag `v1.4.2` → patch `v1.4.3`, minor `v1.5.0`, major `v2.0.0`.
- Highest tag `2.0.0` → patch `2.0.1`, minor `2.1.0`, major `3.0.0`.
- No tags → patch `v0.0.1`, minor `v0.1.0`, major `v1.0.0` (recommended minor).

Mixed prefix conventions: match the highest stable tag. If the repository has
both `v1.2.3` and `2.0.0`, the higher version wins and its prefix is used.
If that produces an unexpected name, ask the user before tagging.
