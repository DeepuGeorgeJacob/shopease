# Spotless Kotlin setup reference

## Contents

- [Requirements and versions](#requirements-and-versions)
- [Version catalog](#version-catalog)
- [Central configuration](#central-configuration)
- [Per-module configuration](#per-module-configuration)
- [Targets and exclusions](#targets-and-exclusions)
- [ktlint and `.editorconfig`](#ktlint-and-editorconfig)
- [Task map](#task-map)
- [Lint failures and suppression](#lint-failures-and-suppression)
- [Ratchet for gradual adoption](#ratchet-for-gradual-adoption)
- [CI recipes](#ci-recipes)
- [Troubleshooting](#troubleshooting)
- [Choosing a Kotlin formatter](#choosing-a-kotlin-formatter)

## Requirements and versions

Spotless is a Gradle plugin plus a formatter step. For Kotlin the usual step
is ktlint.

| Spotless | Minimum JRE | Minimum Gradle | Notes |
| -------- | ----------- | -------------- | ----- |
| 8.x | 17 | 7.3 | Current line; linting supported |
| 7.x | 11 | 6.1.1 | Linting added in 7.0; use 7.2.1 on JRE 11 |
| 6.x | 8 | 6.1.1 | Use 6.13.0 if stuck on JRE 8 |

Verify the current stable versions before pinning:

```bash
curl -fsSL \
  https://repo1.maven.org/maven2/com/diffplug/spotless/spotless-plugin-gradle/maven-metadata.xml \
  | grep -o '<release>[^<]*</release>'

curl -fsSL \
  https://repo1.maven.org/maven2/com/pinterest/ktlint/ktlint-cli/maven-metadata.xml \
  | grep -o '<release>[^<]*</release>'
```

Use the `<release>` value, not a snapshot or milestone. If the project's
Kotlin version is much older than the ktlint version, verify that ktlint
parses the project's Kotlin syntax; when in doubt, pin the ktlint line that
matches the Kotlin language version.

## Version catalog

```toml
[versions]
spotless = "8.12.0"
ktlint = "1.8.0"

[plugins]
spotless = { id = "com.diffplug.spotless", version.ref = "spotless" }
```

`ktlint` is only a version key. Spotless downloads the ktlint artifacts it
needs; do not add ktlint to `dependencies`, `implementation`, or a
`plugins` block. The module that applies Spotless must have a repository
that hosts ktlint (normally `mavenCentral()`); without one the build fails
with `no repositories are defined`.

If the project already has a `spotless` or `ktlint` key, reuse it. Follow the
repository's alias style from the `gradle-version-catalog` skill.

## Central configuration

Recommended for a multi-module repository: apply Spotless once and configure
every Kotlin module from the root build.

```kotlin
import com.diffplug.gradle.spotless.SpotlessExtension

plugins {
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

Why `apply false` in `plugins` and `apply(plugin = ...)` in `subprojects`:
the plugin is resolved once at the root and applied to each module without
repeating the version or the plugin block.

### Covering the root build script

`subprojects` does not include the root project, so the root
`build.gradle.kts` is not checked. Either apply the plugin to the root too:

```kotlin
plugins {
    alias(libs.plugins.spotless)
}

subprojects {
    apply(plugin = "com.diffplug.spotless")
}

spotless {
    kotlinGradle {
        target("*.gradle.kts")
        ktlint(libs.versions.ktlint.get())
    }
}
```

or use `allprojects`:

```kotlin
allprojects {
    apply(plugin = "com.diffplug.spotless")
    configure<SpotlessExtension> { /* shared config */ }
}
```

`allprojects` also configures the root project; keep the configuration
idempotent and free of dependencies.

### Combined Java and Kotlin

A module can have both Java and Kotlin. Add a `java { ... }` block alongside
`kotlin { ... }` and use the same license/whitespace steps where the project
already does:

```kotlin
configure<SpotlessExtension> {
    java {
        target("src/*/java/**/*.java")
        googleJavaFormat()
    }
    kotlin {
        target("src/*/kotlin/**/*.kt")
        ktlint(libs.versions.ktlint.get())
    }
}
```

Do not add Java formatting to a Kotlin-only task unless requested; it changes
unrelated files.

## Per-module configuration

Use this when only some modules should be checked, or when a module needs a
different style.

```kotlin
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.spotless)
}

spotless {
    kotlin {
        target("src/*/kotlin/**/*.kt", "src/*/java/**/*.kt")
        ktlint(libs.versions.ktlint.get())
    }
    kotlinGradle {
        target("*.gradle.kts")
        ktlint(libs.versions.ktlint.get())
    }
}
```

With the Kotlin DSL, `spotless { }` is available directly once the plugin is
applied. If a convention plugin configures it, use
`configure<SpotlessExtension>` there and apply the plugin in each consumer.

## Targets and exclusions

Spotless normally infers Kotlin sources from the Java source sets. Override
the target when inference does not work:

| Project type | Target |
| ------------ | ------ |
| Kotlin JVM / Spring Boot | Default is fine; or `src/*/kotlin/**/*.kt` |
| Android | `src/*/kotlin/**/*.kt`, `src/*/java/**/*.kt` |
| `java-gradle-plugin` | `src/*/kotlin/**/*.kt` |
| Kotlin Gradle scripts | `kotlinGradle { target("*.gradle.kts") }` |
| Root build scripts | Apply the plugin to the root project |

Exclude things that are not source:

```kotlin
kotlin {
    target("src/**/*.kt")
    targetExclude(
        "**/build/**",
        "**/generated/**",
        "**/build/generated/**",
    )
}
```

`targetExclude` takes glob patterns. Never reformat generated code to make
the check pass; exclude it and report the decision.

## ktlint and `.editorconfig`

Spotless reads the top-level `.editorconfig` by default. A minimal Kotlin
section:

```ini
[*.{kt,kts}]
ktlint_code_style = intellij_idea
indent_size = 4
max_line_length = 120
insert_final_newline = true
```

Common overrides:

```kotlin
ktlint(libs.versions.ktlint.get())
    .editorConfigOverride(
        mapOf(
            "ktlint_code_style" to "intellij_idea",
            "indent_size" to 4,
            "max_line_length" to 120,
            "ij_kotlin_allow_trailing_comma" to true,
        )
    )
```

- `editorConfigPath` points at a non-standard `.editorconfig`:
  `.setEditorConfigPath("$projectDir/config/.editorconfig")`.
- `editorConfigOverride` wins over the file. Keep overrides few and
  intentional; prefer the shared file for project-wide style.
- ktlint's `intellij_idea` style is the Spotless default. `ktlint_official`
  is stricter; do not switch styles mid-project without agreement.
- Compose rule sets can be added with `.customRuleSets(listOf(...))` only
  when the project already uses them.

## Task map

| Task | Scope |
| ---- | ----- |
| `spotlessCheck` | All configured formats, all modules |
| `spotlessApply` | Apply all configured formats |
| `spotlessKotlinCheck` | `.kt` sources |
| `spotlessKotlinApply` | Fix `.kt` sources |
| `spotlessKotlinGradleCheck` | `.gradle.kts` scripts |
| `spotlessKotlinGradleApply` | Fix `.gradle.kts` scripts |
| `:<module>:spotlessCheck` | One module |
| `spotlessInstallGitPrePushHook` | Optional pre-push guard |

`check` depends on `spotlessCheck` by default. If a project sets
`enforceCheck false`, report it rather than silently leaving CI unguarded.

## Lint failures and suppression

Spotless 7+ surfaces ktlint violations as lints:

```text
:spotlessKotlinCheck FAILED
  There were 1 lint error(s), they must be fixed or suppressed.
    src/main/kotlin/com/example/Foo.kt:L3 ktlint(standard:function-naming) Function name should start with a lowercase letter
```

Order of resolution:

1. Fix the code.
2. Run `spotlessApply` when the violation is auto-fixable.
3. Suppress a single short code only when the project intentionally violates
   it, and leave a reason in the build file or a nearby comment.

```kotlin
kotlin {
    ktlint(libs.versions.ktlint.get())
    suppressLintsFor {
        step = "ktlint"
        shortCode = "standard:function-naming"
    }
}
```

Use the exact `shortCode` printed in the failure. Some rules are inactive
under the selected code style: `intellij_idea` permits `java.util.*`, so
`standard:no-wildcard-imports` does not fire unless
`ij_kotlin_packages_to_use_import_on_demand` is set.

Do not:

- Suppress a whole rule set or every ktlint lint.
- Add `enforceCheck false` to hide failures.
- Remove `spotlessCheck` from `check` in CI.
- Reformat generated files to silence a failure.

## Ratchet for gradual adoption

```kotlin
configure<SpotlessExtension> {
    ratchetFrom("origin/main")
}
```

- Only files changed since `origin/main` are checked.
- Use a remote ref or tag, not `HEAD` or a local branch; local refs move as
  soon as you commit.
- CI needs full history: `actions/checkout` with `fetch-depth: 0`.
- Ratcheting is a migration tool. Once the baseline is formatted, remove it
  so all files stay enforced.
- `ratchetFrom` can also be set per format.

## CI recipes

### GitHub Actions

```yaml
name: lint
on: [push, pull_request]

jobs:
  spotless:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0 # required only with ratchetFrom
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21
      - uses: gradle/actions/setup-gradle@v4
      - run: ./gradlew spotlessCheck
```

### GitLab CI

```yaml
spotless:
  image: eclipse-temurin:21-jdk
  script:
    - ./gradlew spotlessCheck
```

Rules:

- CI runs `spotlessCheck` (or `check`), never `spotlessApply`.
- Cache Gradle to keep the ktlint artifact download cheap.
- Keep the JDK aligned with the project toolchain; Spotless needs JRE 17+.
- Do not add `--continue` to hide a failing format check.

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| `Task 'spotlessCheck' not found` | Plugin not applied to that project | Apply it in root `subprojects`, `allprojects`, or the module |
| `spotlessKotlinCheck` passes but `.kts` fails | `kotlinGradle` not configured | Add a `kotlinGradle` block targeting `*.gradle.kts` |
| No Kotlin files are checked | Wrong `target`, or Android/gradle-plugin sources | Set an explicit `target`; run with `--info` to see matched files |
| Root `build.gradle.kts` is not checked | Plugin applied only to `subprojects` | Apply to the root or use `allprojects` |
| ktlint artifact cannot be downloaded | Offline/proxy/repository issue | Verify network and repositories; retry with `--refresh-dependencies` |
| `no repositories are defined` | Module has no repository for the ktlint artifact | Add `mavenCentral()` (or the project mirror) to that module |
| Lint errors remain after `spotlessApply` | ktlint lint is not auto-fixable | Fix the code or suppress the specific short code |
| `.editorconfig` seems ignored | Wrong location or override | Check `editorConfigPath`; remember overrides win |
| CI ratchet sees no changes | Shallow clone | Set `fetch-depth: 0` |
| IDE formatting differs from Spotless | Different ktlint version or style | Align the IDE plugin version/style with the build |
| Spotless fails with an internal error | Version/JDK/Gradle mismatch | Check the requirements table; rerun with `--stacktrace` |

## Choosing a Kotlin formatter

| Tool | What it does | When to use |
| ---- | ------------ | ----------- |
| ktlint (via Spotless) | Formats and enforces Kotlin style rules | Default for lint/format checks |
| ktfmt (via Spotless) | Formats only (Google/Meta style) | Project already uses ktfmt |
| detekt | Static analysis (complexity, smells, bugs) | Complementary; not a formatter |

Do not run ktlint and ktfmt on the same sources. Do not replace a project's
existing formatter just to add a lint check; configure the formatter already
in use. detekt does not replace `spotlessCheck`; if both exist, both can run
under `check`.
