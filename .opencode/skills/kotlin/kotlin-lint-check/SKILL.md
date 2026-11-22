---
name: kotlin-lint-check
description: Set up, run, and troubleshoot Kotlin lint and format checks with
  Spotless and ktlint in a Gradle build. Adds the Spotless plugin and version
  catalog entries, configures Kotlin sources and Kotlin Gradle scripts, wires
  spotlessCheck into check and CI, applies fixes locally, and handles lint
  failures and narrow suppressions. Use when adding Kotlin formatting or lint
  enforcement, fixing spotlessCheck / spotlessKotlinCheck failures, or
  configuring ktlint rules. Spotless formats and lints; it does not check
  hyperlinks.
---

# Kotlin Lint Check with Spotless

## Purpose

Enforce Kotlin formatting and lint rules through **Spotless + ktlint** in a
Gradle build. The lint check is:

```bash
./gradlew spotlessCheck
```

`spotlessApply` fixes what can be fixed automatically. Since Spotless 7,
ktlint rule violations are reported as **lints** and fail the build, so a
green `spotlessCheck` means formatting and lint rules both pass. Spotless
does not validate hyperlinks or URLs; if the user asks for link checking,
say so and use a link checker instead.

Detailed configuration variants, task names, CI snippets, and
troubleshooting live in `references/spotless-kotlin-setup.md`.

## Project facts to confirm, not assume

1. **Gradle and JVM versions.** Spotless 8 requires JRE 17+ and Gradle 7.3+.
   On JRE 11 pin Spotless 7.2.1 or older; on JRE 8 pin 6.13.0 or older. Do
   not upgrade Gradle or the JDK just to enable linting unless asked.
2. **Kotlin layout.** Which modules contain Kotlin sources? Is the Kotlin
   plugin applied once in the root `subprojects` block or per module? Any
   Android or `java-gradle-plugin` modules (their sources are not inferred
   automatically)?
3. **Version catalog.** Existing alias and version-key style in
   `gradle/libs.versions.toml`.
4. **Existing tooling.** Is Spotless, ktlint, ktfmt, or detekt already
   configured? Is there a `.editorconfig`? Has `check` been customized
   (for example `enforceCheck false`)?
5. **Generated sources.** KSP, OpenAPI, build output, or vendored code that
   must not be reformatted.
6. **CI.** Workflow file, JDK, Gradle caching, and whether full git history
   is available (needed for `ratchetFrom`).

## Workflow

### 1. Choose the enforcement scope

- **All Kotlin modules (recommended):** apply Spotless once in the root
  build and configure it centrally, matching how this repository applies
  `java` in `subprojects`.
- **Selected modules:** apply and configure Spotless in those build files
  only.
- **Gradual adoption:** add `ratchetFrom("origin/main")` so only changed
  files are enforced. Remove the ratchet after the baseline is clean.
- **Never target** `build/`, generated sources, or vendored code.

### 2. Add catalog entries

```toml
[versions]
spotless = "8.12.0"
ktlint = "1.8.0"

[plugins]
spotless = { id = "com.diffplug.spotless", version.ref = "spotless" }
```

- `ktlint` is a version key consumed by Spotless, **not** a Gradle plugin.
  Never add ktlint to `dependencies`.
- Pin both versions. Verify the current stable release before writing
  them (see the reference file); do not guess or use a floating version.
- Reuse existing keys/aliases instead of adding duplicates.

### 3. Apply and configure in the root build

```kotlin
import com.diffplug.gradle.spotless.SpotlessExtension

plugins {
    // Resolved once; applied per module below.
    alias(libs.plugins.spotless) apply false
}

subprojects {
    apply(plugin = "com.diffplug.spotless")

    configure<SpotlessExtension> {
        kotlin {
            target("src/*/kotlin/**/*.kt", "src/*/java/**/*.kt")
            targetExclude("**/build/**")
            ktlint(libs.versions.ktlint.get())
                .editorConfigOverride(
                    mapOf(
                        "ktlint_code_style" to "intellij_idea",
                        "indent_size" to 4,
                    )
                )
        }

        kotlinGradle {
            target("*.gradle.kts")
            ktlint(libs.versions.ktlint.get())
        }
    }
}
```

Rules:

- The `SpotlessExtension` import is required for
  `configure<SpotlessExtension>` in the Kotlin DSL.
- `subprojects` does not cover the root `build.gradle.kts`. Apply the plugin
  to the root as well (or use `allprojects`) if root build scripts should be
  checked.
- Android and `java-gradle-plugin` sources need an explicit `target(...)`;
  Spotless cannot infer them.
- `ktlint()` with no argument uses the version bundled with Spotless. Pass
  the pinned catalog version for reproducibility.
- Spotless downloads ktlint from the project's repositories. Every module
  that applies Spotless needs `mavenCentral()` (or the project's mirror)
  available; otherwise the build fails with "no repositories are defined".
- Keep the root free of dependencies; this is plugin configuration only.
- Per-module alternative: apply `alias(libs.plugins.spotless)` and configure
  `spotless { ... }` in that module's build file.

### 4. Add or extend `.editorconfig`

```ini
[*.{kt,kts}]
ktlint_code_style = intellij_idea
indent_size = 4
max_line_length = 120
insert_final_newline = true
```

Spotless reads the top-level `.editorconfig` by default. Extend the existing
file; do not replace project style with a new one. `editorConfigOverride`
wins over the file, so use it for a small number of deliberate overrides.

### 5. Run the check and apply fixes

```bash
./gradlew spotlessCheck
./gradlew spotlessApply
./gradlew :shop-service:spotlessKotlinCheck
./gradlew :shop-service:spotlessKotlinGradleCheck
./gradlew check
```

- `spotlessCheck` / `spotlessApply` are aggregate tasks across formats.
- Per-format tasks follow
  `<module>:spotless<Format>Check` / `Apply`.
- `check` depends on `spotlessCheck` by default. Do not disable that.
- After `spotlessApply`, inspect the diff and rerun `spotlessCheck`.

A helper wrapper is in `scripts/run-spotless-check.sh`:

```bash
scripts/run-spotless-check.sh
scripts/run-spotless-check.sh --apply
scripts/run-spotless-check.sh --module shop-service
```

### 6. Handle failures correctly

- **Format violation:** run `spotlessApply`, review the diff, rerun
  `spotlessCheck`.
- **Lint error:** ktlint lints are not always auto-fixable. Fix the code,
  or suppress one narrow rule with a comment explaining why:

  ```kotlin
  kotlin {
      ktlint(libs.versions.ktlint.get())
      suppressLintsFor {
          step = "ktlint"
          shortCode = "standard:function-naming"
      }
  }
  ```

  Use the exact short code printed in the failure. Some rules are inactive
  under the selected style: for example `intellij_idea` permits
  `java.util.*`, so `standard:no-wildcard-imports` will not fire.

- **Generated file failing:** exclude its path with `targetExclude`; do not
  reformat generated output.
- **Version/crash problems:** confirm the pinned ktlint and Spotless
  versions, JDK, and Gradle version, then rerun with `--stacktrace`.
- Never make the build green by disabling whole rule sets or
  `enforceCheck`.

### 7. Enforce it in CI

```yaml
- uses: actions/setup-java@v4
  with:
    distribution: temurin
    java-version: 21
- uses: gradle/actions/setup-gradle@v4
- run: ./gradlew spotlessCheck
```

- Run `spotlessCheck` (or `check`), **never `spotlessApply`**, in CI.
- Set `fetch-depth: 0` when `ratchetFrom` is enabled.
- Optional local guard: `./gradlew spotlessInstallGitPrePushHook`.

### 8. Validate — actually run these

```bash
./gradlew spotlessCheck
./gradlew spotlessApply
git diff --stat
./gradlew spotlessCheck
./gradlew check
```

- The first `spotlessCheck` may fail before fixes; the final one must pass.
- A second `spotlessApply` must produce no further changes.
- The diff contains only expected Kotlin/build-script changes.
- Generated and vendored files are untouched.
- `check` still passes, including tests.

Do not report success for a step that was skipped or failed.

## Guardrails

- **Lint, not links.** Spotless enforces formatting and ktlint rules; it does
  not check URLs or hyperlinks.
- **No mass reformatting.** Do not reformat unrelated files in a feature
  change. Use `ratchetFrom` or a dedicated formatting commit with approval.
- **No rule disabling.** Do not turn off ktlint rules, `enforceCheck`, or
  `spotlessCheck` to hide violations. Suppress only a specific short code
  with a justification.
- **No `spotlessApply` in CI.** CI verifies; developers apply.
- **No ktlint dependency.** Spotless resolves and runs ktlint.
- **No generated sources.** Exclude build output, KSP/OpenAPI output, and
  vendored code.
- **No guessed versions.** Verify Spotless and ktlint versions from Maven
  Central, and keep them pinned.
- **No unrelated upgrades.** Do not bump Kotlin, Spring Boot, Gradle, or the
  JDK as part of enabling linting unless the user requested it.
- **Respect existing style.** Extend `.editorconfig` and mirror the
  repository's conventions rather than imposing a new code style.
- **Keep `check` authoritative.** `spotlessCheck` must remain part of
  `check` so local and CI builds enforce the same rules.

## Final response format

- **Plugin/config:** Spotless and ktlint versions, scope (root/central or
  per module), files changed.
- **Targets:** formats configured and excluded paths.
- **Editor config:** created or changed keys.
- **CI:** workflow file and command added.
- **Validation:** exact Gradle commands run and their result, including
  failures.
- **Suppressions/follow-ups:** narrow lint suppressions, files left
  unformatted, or ratchet removal still pending.
