---
name: Tag Push
description: Create and push a release tag - verify a strict release gate, suggest the next semantic version from existing tags, create an annotated tag, push only that tag to origin, and verify it. Use when the user asks to tag a release, create a git tag, push a tag, or publish a version.
---

# Tag Push

## Purpose

Publish **exactly one** release tag for the current commit. The skill checks
that the commit is safe to release, proposes the next semantic version based on
the tags already in the repository, asks for confirmation, then creates an
annotated tag, pushes only that tag to the configured remote, and verifies the
result.

This skill is the home for git tagging. Keep it beside `../git-workflow`, which
handles pushing commits. A tag is immutable once published: every check below
is meant to prevent a mistaken or overwritten release.

Run the scripts in this skill **from this skill's base directory** (the
directory containing `SKILL.md`). Paths below are relative to it.

## Non-negotiable rules

1.  **Strict release gate.** Stop unless the worktree is clean, `HEAD` is
    merged into the base branch on the remote, and the chosen tag does not
    exist locally or on the remote. Never bypass a failed check.
2.  **Never overwrite a tag.** No `git tag -f`, no `git push --force`, no
    `-f`/`--force` with a tag ref. If a tag already exists locally or remotely,
    stop and report it; deleting or moving published tags is a separate,
    explicitly confirmed operation outside this skill.
3.  **Push one ref only.** Use `git push <remote> refs/tags/<tag>`. Never use
    `git push --tags` or push branches as part of a tag push.
4.  **Annotated tags only.** Create the tag with `git tag -a` and a release
    message. Lightweight tags are not valid release tags here.
5.  **Confirm the exact tag before creating it.** The version suggestion is a
    recommendation, not a decision. The user picks the final tag name.
6.  **Tag only reviewed code.** The tag must point at the exact `HEAD` that was
    inspected. Never move `HEAD`, stash, reset, or clean to satisfy a check.
7.  **Never tag a commit that is not on the remote base branch.** If `HEAD` is
    not an ancestor of `origin/<base>`, stop and ask; do not tag a local-only
    or unmerged feature branch.
8.  **Never invent a version.** Derive candidates from actual tags with
    `scripts/next-version.sh`. If the user supplies a name that is not valid
    semantic versioning, ask again rather than silently rewriting it.

## Step 0: Identify the base and refresh tags

```sh
git fetch origin --prune --tags
```

- Determine the base branch from `origin/HEAD`; if it is not set, use `main`
  (or the base branch the repository/user names). Record it as `<base>`.
- Use a different `<remote>` throughout if the user names one; the default is
  `origin`.
- If the fetch fails (no remote, no credentials), stop and report the exact
  error. Do not continue with stale refs.

## Step 1: Run the strict release gate

```sh
bash scripts/inspect-tag-repo.sh --remote origin --base <base>
```

The inspector is read-only and prints the remote, base ref, current branch,
`HEAD`, worktree state, ahead/behind counts, the latest stable semver tag, and
a `GATE:` line. It exits non-zero when the gate fails.

Handle the result:

- **Dirty worktree:** list the changed files from the output and stop. Do not
  stash, commit, or clean them as part of this skill.
- **`HEAD` not merged into `origin/<base>`:** stop. Show the ahead/behind
  counts and tell the user to land the commit on `<base>` first.
- **`HEAD` behind the base tip:** the gate passes, but the tag would point at
  an older commit. Ask the user to confirm the commit shown in the output
  before continuing; recommend tagging the current base tip instead.
- **Detached `HEAD`:** allowed only if the gate passes; include the exact
  commit SHA in the confirmation question.
- **No stable tags yet:** continue; `scripts/next-version.sh` handles a first
  release.

If the gate passes, record the full `HEAD` SHA from the output. The tag will be
created at that SHA.

## Step 2: Propose the next version

```sh
bash scripts/next-version.sh
```

The script prints the latest stable tag, the detected `v` prefix convention,
`patch`, `minor`, and `major` candidates, and a `recommended` value. See
`references/versioning.md` for the rules it follows.

Use the `question` tool with header `Release tag`:

- Ask: `Tag <short-sha> (<base>) as which version? Latest tag: <latest or none>.`
- First option: use the `recommended` candidate, with the exact tag name in the
  description, labelled `(Recommended)`.
- Add the other bump options as alternatives, each with its exact tag name.
- The built-in free-form answer lets the user type an exact tag name.

Validate the chosen tag against `^v?[0-9]+\.[0-9]+\.[0-9]+$` (a `v` only when
the repository uses that prefix). Accept a prerelease/build suffix only when
the user explicitly typed one and confirmed it in a follow-up question. Do not
create the tag until the user answers.

If the user gave an explicit valid tag in the original request, skip the
question and use it, still reporting the derived candidates.

## Step 3: Recheck with the chosen tag

```sh
bash scripts/inspect-tag-repo.sh --remote origin --base <base> --tag <tag>
```

This re-runs the gate and additionally confirms the tag is absent both locally
and on the remote. If it exists in either place, stop and report where; never
force through the push.

## Step 4: Create the annotated tag

```sh
git tag -a <tag> -m "Release <tag>" <recorded-head-sha>
git cat-file -t refs/tags/<tag>   # must print: tag
```

- Use the recorded `HEAD` SHA, not a moving ref.
- Default message is `Release <tag>`. If the user supplied a release message,
  use that instead.
- If `git cat-file -t` does not print `tag`, stop; a lightweight tag is not a
  valid result here.

## Step 5: Push only that tag

```sh
git push origin refs/tags/<tag>
```

- Do not use `--tags` and do not include a branch ref.
- If the push is rejected (permissions, existing remote tag, hook), stop and
  report the exact error. Do not retry with `--force`.
- Record the push output for the final report.

## Step 6: Verify

```sh
bash scripts/verify-tag.sh <tag> origin
```

The verifier confirms the tag is annotated, resolves to the recorded commit,
exists on the remote, and that the worktree is still clean. It prints `PASS:`
on success and exits non-zero with `FAIL:` on any mismatch. A failed
verification is a release incident: report it clearly and do not delete or
rewrite the tag on your own.

## Step 7: Report

Summarize:

- tag name, tag message, type (annotated), and the exact commit it points to
- base branch and how the release gate passed (clean tree, merged commit)
- push result, remote name/URL, and the verification output
- follow-ups, when relevant: publish GitHub release notes, update a changelog,
  trigger deployment, or announce the version

## Failure handling

- **Not a git repo / no remote / fetch failure:** stop with the exact error.
- **Dirty worktree:** list files, stop, do not stash or commit them.
- **Unmerged or local-only commit:** stop and ask the user to land it on the
  base branch first.
- **Tag already exists locally or remotely:** stop, show both locations, and
  ask before any other action. Never overwrite.
- **Invalid user-supplied tag:** explain the semver rule and ask again.
- **Rejected push or failed verification:** report verbatim; do not force,
  delete, or recreate the tag without explicit user confirmation.
- **User declines the version:** leave everything local and report that no tag
  was created or pushed.
