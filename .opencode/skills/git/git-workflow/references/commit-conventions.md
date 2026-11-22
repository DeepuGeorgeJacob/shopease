# Commit and branch conventions

## Message format

```text
<type>(<scope>): <summary>

<optional body, wrapped at 72 columns>

<optional footer>
```

## Types

| Type       | Use for                                                        | Example                                    |
| ---------- | -------------------------------------------------------------- | ------------------------------------------ |
| `feat`     | New user-visible behavior or capability                        | `feat(catalog): add product search`        |
| `fix`      | Bug fix or incorrect behavior                                  | `fix(cart): keep totals after refresh`     |
| `chore`    | Maintenance, dependencies, config, tooling, housekeeping       | `chore(deps): bump spring boot to 4.0.1`   |
| `refactor` | Code change that is neither a feature nor a fix                | `refactor(orders): extract price calculator` |
| `docs`     | Documentation only                                             | `docs: document local run steps`           |
| `test`     | Tests only                                                     | `test(cart): cover empty checkout`         |
| `build`    | Build system, Gradle files, packaging                          | `build: enable configuration cache`        |
| `ci`       | CI/CD configuration                                            | `ci: run tests on pull requests`           |
| `perf`     | Performance improvement                                        | `perf(catalog): cache category lookups`    |
| `style`    | Formatting or whitespace only                                  | `style: apply ktfmt to module`             |
| `revert`   | Revert a previous commit                                       | `revert: feat(catalog): add product search` |

## Choosing the type

- Adds new behavior or an endpoint -> `feat`
- Corrects wrong behavior -> `fix`
- Only names, formatting, or structure changed -> `refactor` / `style`
- Dependencies, Gradle wrapper, config, ignore files -> `chore` / `build`
- Documentation or comments only -> `docs`
- Tests only -> `test`
- Pipelines and automation -> `ci`
- Measurably faster or lighter -> `perf`

When a change spans several types, pick the type that describes the primary
user-facing effect. Do not invent a type outside the list above.

## Summary

- Imperative mood: `add`, `fix`, `remove`, `rename` (not `added` or `adds`).
- Lowercase first letter.
- No trailing period.
- 72 characters or fewer for the whole first line.
- Describe the effect, not the implementation detail.
- Do not mention file names unless they are meaningful to a reviewer.

## Scope

- Optional and lowercase, no spaces.
- Use the module, package, or feature area touched: `catalog`, `orders`,
  `cart`, `auth`, `api`, `deps`, `build`, `docs`.
- Omit the scope when the change is cross-cutting.

## Body and footers

- Use a body only when the reason is not obvious from the summary.
- Reference issues in the footer, for example `Refs: #42` or `Closes: #42`.
- Breaking changes use `!` after the type/scope and a footer:

```text
feat(api)!: remove legacy checkout endpoint

BREAKING CHANGE: clients must call POST /v2/checkout instead.
```

## Branch names

Use `<type>/<short-slug>` with the same type as the commit:

- `feat/product-search`
- `fix/cart-total-refresh`
- `chore/bump-spring-boot`
- `docs/run-instructions`

Slug rules: lowercase kebab-case, 2--5 words, no ticket IDs unless the
repository already uses them. Never use `main` or `master`.

## Protected branches

`main` is the default branch and is protected:

- No commits, merges, rebases, or amends on `main`.
- No pushes to `main`, including `--force` and `--force-with-lease`.
- Work happens on `<type>/<slug>` branches and reaches `main` through a pull
  request.
- The protected list can be extended with `GIT_PROTECTED_BRANCHES`
  (default: `main master`).
