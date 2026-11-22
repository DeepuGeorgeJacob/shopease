---
name: Git Workflow
description: Manage the git workflow for shipping code: create a separate branch, squash all work into one Conventional Commit, rebase it onto the latest main, and push. Use when the user asks to push code, commit and push, ship work, or publish a branch.
---

# Git Workflow

## Purpose

Turn the current working state into **exactly one** reviewable commit on a
separate branch based on the latest base branch (`main` unless the repository
uses another), then push that branch to the configured remote.

The default branch is `main`. `main` is protected: committing or pushing to it
must fail with an error, never succeed silently.

This skill is the home for the repository's git workflow. Add new workflow
steps and policies here as the project evolves, keeping the push flow below as
the core path.

## Non-negotiable rules

1.  **`main` is protected.** Never commit, merge, rebase, amend, or push `main`
    (or `master`). If the current branch is `main`/`master`, stop the commit or
    push with an explicit error and create a feature branch instead.
2.  Never push to any base branch, even with `--force-with-lease`.
3.  The pushed branch must contain exactly one commit on top of
    `origin/<base>`.
4.  Never use `git push --force`. Rewriting your own already-pushed feature
    branch uses `git push --force-with-lease`.
5.  Never use `git reset --hard` or `git clean`. If an operation cannot be
    done safely, stop and ask.
6.  Always ask the user for the commit message, with a recommended message,
    before creating the commit.
7.  Never commit secrets, credentials, `.env` files, build output, or editor
    state. Stop and ask if the diff looks suspicious.
8.  Do not rewrite, rebase, or force-push a branch you did not create or that
    already has an open pull request unless the user explicitly confirms.
9.  **Never push tags.** Tag pushes are blocked by the `pre-push` hook. If a
    push would include tag refs (`git push --tags`, `push.followTags`, or an
    explicit `refs/tags/...` refspec), ignore those tag refs and push only the
    branch. Do not bypass the hook with `--no-verify`.

## Step 0: Protect the default branch

`main` is protected. Enforce this with the guard immediately before any
commit or push:

```sh
bash scripts/guard-branch.sh              # checks the current branch
bash scripts/guard-branch.sh --target <branch>   # checks a push target
```

The guard exits non-zero when `HEAD` or the target is `main`/`master` and
prints an error.

- **Explicit request to commit or push `main`:** run the guard first, show the
  error, and refuse. Do not silently move the work to a branch unless the user
  agrees.
- **Normal "push my work" while on `main`:** creating the feature branch in
  Step 3 is the expected path. That is allowed; the guard must pass by the time
  the actual commit and push happen.
- A guard failure at any later step stops the workflow; report the error and
  do not retry with `--no-verify` or force flags.

## Step 1: Inspect

From the skill's base directory, run the read-only inspector:

```sh
bash scripts/inspect-repo.sh
```

Record:

- remote URL and base reference (`origin/main`, `origin/master`, or
  `origin/HEAD`)
- current branch (`<detached HEAD>` is possible)
- commits ahead of and behind the base
- staged, unstaged, and untracked changes

Review the actual diff (`git diff` and `git diff --cached`) before staging.
If there is nothing to push (clean tree and no commits ahead of the base),
tell the user and stop.

If the change set contains secrets, credentials, large binaries, or generated
output, stop and ask before staging. Respect `.gitignore`; do not add ignored
files with `-f`.

## Step 2: Refresh the base

```sh
git fetch origin --prune
```

Recompute the base reference after the fetch. If the repository or the user
names a different base branch, use that instead.

## Step 3: Choose the branch

Follow `references/commit-conventions.md` for type names and branch slugs.

- If the user gave a branch name, use it.
- If already on a feature branch for this work, reuse it.
- Otherwise create `<type>/<short-slug>`, for example:

```sh
git switch -c feat/add-product-search origin/main
```

Branch rules:

- Never create or use `main`, `master`, or another base branch.
- Keep the slug lowercase kebab-case, 2--5 words.
- If the branch already exists locally or on the remote, choose a different
  slug or ask; never mix in unrelated work.
- When leaving the base branch with uncommitted changes, create the branch
  from the freshly fetched base so the changes sit on top of it. If git
  refuses because the changes conflict with the new base, stop and ask instead
  of discarding them.

## Step 4: Squash to one commit

Goal: after this step `git rev-list --count origin/<base>..HEAD` is `1`.

Recommended sequence:

```sh
bash scripts/guard-branch.sh   # must pass: never squash onto main
git add -A
# Only if something was staged, checkpoint so the rebase runs on a clean tree:
git commit -m "chore: wip checkpoint"
git rebase origin/<base>
git reset --soft origin/<base>   # collapse all work into staged changes
```

- If `git commit` reports nothing to commit, skip the checkpoint commit.
- The checkpoint commit never reaches the remote; the soft reset removes it.
- Never stage unrelated files the user did not touch.
- If the rebase conflicts, stop, list the conflicted files, and ask the user
  how to proceed. Only run `git rebase --abort` after telling the user; it
  returns to the checkpoint state.

## Step 5: Ask for the commit message

Before committing, derive a recommendation from the staged diff
(`git diff --cached --stat` and `git diff --cached`).

Use the `question` tool with the header `Commit message`:

- Ask: `What commit message should I use? Recommended: "<message>"`
- First option: `Use recommended message` (Recommended), with the exact
  recommended message in its description.
- Add one or two alternatives with plausible types when genuinely ambiguous.
- The built-in free-form answer lets the user type their own message.

Format: `<type>(<scope>): <summary>`. See
`references/commit-conventions.md`. Requirements:

- prefix must be one of `feat`, `fix`, `chore`, `refactor`, `docs`, `test`,
  `build`, `ci`, `perf`, `style`, `revert`
- summary in imperative mood, lowercase, no trailing period, 72 characters or
  fewer for the first line
- scope optional; use the module or feature area (`catalog`, `orders`, `auth`,
  `build`, ...)

If the user's answer has no valid prefix, apply the most appropriate type and
state the final message in the summary.

Do not commit until the user answers.

## Step 6: Commit

```sh
bash scripts/guard-branch.sh
git commit -m "<confirmed message>"
```

Verify the single-commit invariant:

```sh
git log --oneline origin/<base>..HEAD
git status --short
```

If more than one commit is listed, repeat the squash in Step 4 before pushing.

## Step 7: Rebase onto the latest base

```sh
git fetch origin --prune
git rebase origin/<base>
```

If the base moved and the rebase rewrites the commit, confirm the branch still
has exactly one commit ahead of the base. On conflict, stop and ask; never
force a resolution the user did not approve.

## Step 8: Push

```sh
bash scripts/guard-branch.sh                 # HEAD must not be main/master
bash scripts/guard-branch.sh --target <branch>  # target must not be main/master
git push -u --no-tags origin refs/heads/<branch>:refs/heads/<branch>   # first push
git push --no-tags origin refs/heads/<branch>:refs/heads/<branch>      # later pushes
```

- Use an explicit branch refspec with `--no-tags` so only the branch is
  published. If tags exist locally or are awaiting push, ignore them: never
  include `refs/tags/...` or `--tags` in this workflow, and do not delete or
  move local tags to work around the hook.
- If either guard fails, show the error and do not push.
- If the push is rejected because the branch was rewritten and it is your own
  feature branch, use
  `git push --force-with-lease --no-tags origin refs/heads/<branch>:refs/heads/<branch>`.
  Never use `--force`.
- Never push to the base branch.
- If `gh` is available and the user wants a PR, report the compare URL and
  offer `gh pr create`.

## Step 9: Report

Summarize:

- branch name and base branch
- the single commit hash and message
- files changed (`git show --stat --oneline HEAD`)
- push result, remote branch, and compare URL if available
- sensible follow-ups (open PR, run CI, request review)

## Local enforcement (recommended)

The guard only runs when the agent follows this skill. To block `main` even for
manual `git commit` / `git push`, install the repository hooks:

```sh
bash scripts/install-hooks.sh
```

This installs:

- `.git/hooks/pre-commit` — aborts any commit made while on `main` or `master`.
- `.git/hooks/pre-push` — aborts any push that updates `main`/`master`, even
  when pushed from another branch, and aborts any push that publishes tags.

Hooks are local to this clone. Offer to install them once per repository, and
mention it in the final report. The protected list can be overridden with the
`GIT_PROTECTED_BRANCHES` environment variable (default: `main master`).

## Failure handling

- **Not a git repo, no remote, no push permission:** stop and report the exact
  error.
- **Current branch is `main`/`master`:** show the guard error, refuse the
  commit/push, and offer to create a feature branch.
- **Push targets `main`/`master`:** show the guard error and refuse. Never
  force this through.
- **Detached HEAD:** ask whether to branch from `HEAD` or from the base, then
  proceed.
- **Merge/rebase conflicts:** stop, list conflicted files, ask. Do not
  force-push and do not discard work.
- **User declines the push:** leave the commit local and report the branch and
  message.
- **Ambiguous scope:** prefer the smaller change set; ask when unsure.
