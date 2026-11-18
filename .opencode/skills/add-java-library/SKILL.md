---
name: Add Java Library
description: Add a new Java library/dependency to a Gradle multi-module
  Spring Boot project. Verifies the coordinate and version against Maven
  Central and the Spring Boot BOM, adds or reuses a version-catalog entry,
  wires it into the correct module and configuration (api, implementation,
  testImplementation, and so on), and validates that it resolves. Use when
  adding, upgrading, or wiring a third-party Java dependency.
---

# Add a Java Library

## Purpose

Add one new third-party Java library to this project without breaking the
catalog convention, the Spring Boot BOM, or module boundaries. Every
dependency is declared once in `gradle/libs.versions.toml` and referenced
from module build files through `libs.*` accessors.

Catalog mechanics (purging, renaming, bundles, duplicates) live in the
`gradle-version-catalog` skill. Load that skill when the task is a pure
catalog edit; this skill covers the end-to-end "library now resolves in a
module" workflow.

## Project facts to confirm, not assume

Read these before editing; they define what "correct" means here.

1. `gradle/libs.versions.toml` — the one shared catalog. Note the alias
   style, ordering, quoting, and whether a `spring-boot` version key
   exists.
2. Root `build.gradle.kts` — declares plugins with `apply false` and
   configures `subprojects` (Java toolchain, `mavenCentral()`, JUnit
   Platform). It must never gain application `dependencies { }`.
3. `settings.gradle.kts` — the module list (`include(":app", ...)`).
4. The target module's `build.gradle.kts` — which plugin it applies
   (`java-library` vs `org.springframework.boot`), its existing
   configuration choices, and whether it already has the BOM via
   `platform(libs.spring.boot.dependencies)`.

If no module applies the BOM yet, the module needs
`implementation(platform(libs.spring.boot.dependencies))` (or `api` in a
shared module) before any versionless starter will resolve.

## Workflow

### 1. Resolve the request into group, artifact, version, module, configuration

Ask only when a value is genuinely missing. Do not invent versions.

- **Coordinates** — `group:artifact`, exactly as published.
- **Version** — from the user, from the Spring Boot BOM, or verified via
  the script in step 2. Never copy a version from a blog post or from
  memory.
- **Module** — the module that owns the code needing the API, not the
  module that happens to be convenient.
- **Configuration** — see `references/configuration-guide.md`.

### 2. Verify the coordinate and version

Run the helper (paths are relative to this skill's directory):

```bash
scripts/verify-dependency.sh <group:artifact>            # latest release + BOM status
scripts/verify-dependency.sh <group:artifact> <version>  # also assert the version exists
```

The script queries Maven Central and, when a catalog is present, checks
whether the current Spring Boot BOM manages the artifact — following
imported BOMs (`jackson-bom`, `junit-bom`, ...) and inherited POM
properties. Treat its output as the version authority:

- `managed=true` → add a **versionless** catalog entry.
- `managed=false` → add an explicit `version = "..."` or a `[versions]`
  key with `version.ref`.
- `managed_version_unresolved=true` → the BOM pins it indirectly; keep the
  entry versionless and do not invent a number.
- Use `latest_stable`, not `latest_release`: `latest_release` can be a
  milestone (`6.2.0-M1`). Never select `-RC`, `-M`, `-SNAPSHOT`, `-alpha`,
  or `-beta` unless the user asked for it.
- `version_exists=false` or exit code 1 → that coordinate/version is not
  published; pick a real one or ask.

The BOM check needs `python3`; when it is missing the script prints
`bom_checked=false` and you must treat management status as unknown rather
than assuming either way.

### 3. Reuse or create the catalog entry

Search before adding:

```bash
grep -n "artifact-id" gradle/libs.versions.toml
```

- Same module already present → reuse its alias; do not add a second alias
  for the same `group:artifact`.
- Same version used by three or more related entries → add a shared
  `[versions]` key; otherwise `version.ref` to an existing key, or an
  inline version when the project convention favors that.
- Insert next to related entries, preserving surrounding blank lines and
  ordering. Do not reformat unrelated lines.

**Alias rules**

- Lowercase kebab-case, derived from the artifact (`jackson-databind`).
- Drop redundant vendor prefixes only when the project already does so.
- Accessors nest on `-`, `_`, and `.`:
  `spring-boot-starter-web` → `libs.spring.boot.starter.web`.
- An alias must not be a prefix of another alias. Declaring both
  `jackson` and `jackson-databind` produces colliding accessors; use
  `jackson-databind` and `jackson-core` instead.
- Groups must not collide with a library alias either: `test` (library)
  plus `test-fixtures` is a conflict.

### 4. Wire it into the module build file

Add the configuration line in the module that owns the need:

```kotlin
dependencies {
    implementation(libs.jackson.databind)
}
```

Rules:

- Respect the module's plugin. `api` exists only with `java-library`;
  a `java`-only module (or the Spring Boot app module without
  `java-library`) uses `implementation`.
- Never put application dependencies in the root `build.gradle.kts`.
- Never add `repositories { }` to a module; the root `subprojects` block
  provides `mavenCentral()`.
- Never repeat a version in the module build file. Versions live in the
  catalog only.
- Do not add `platform(...)` to the same file twice.

### 5. Validate — actually run these

```bash
./gradlew :<module>:dependencies --configuration <configuration> | grep -i <artifact>
./gradlew :<module>:compileJava
```

- Resolution output must show the artifact at the expected version, with
  no `FAILED` entries.
- For `testImplementation`, use `testCompileClasspath` or `testRuntimeClasspath`.
- Compile the module, not the whole build, unless the user asked for a
  full `./gradlew build`.
- If the catalog changed but accessors do not resolve, the build script
  is stale: re-run the Gradle invocation (accessors are generated during
  configuration) before concluding the alias is wrong.

Do not report success for a step that was skipped or failed.

## Guardrails

- **No guessed versions, ever.** If the script cannot confirm a version,
  stop and ask.
- **No duplicate aliases** for one coordinate; no `version =` and
  `version.ref` on the same entry.
- **No unrelated upgrades.** Adding a library must not bump other
  dependencies or plugins.
- **No silent substitutions.** If the requested artifact is already
  managed at a different version by the BOM and the user wants their own
  version, say so and confirm the override before writing it.
- **Respect module boundaries.** A dependency used by feature code belongs
  in that feature module, exported with `api` only if its types appear in
  that module's public signatures.
- **Do not delete** a version key while other entries still reference it.

## Final response format

- **Library:** `group:artifact:version` (and whether the version is
  BOM-managed).
- **Catalog:** alias added/reused, version key added/reused.
- **Module:** file changed, configuration chosen and why.
- **Validation:** exact Gradle commands run and their result.
- **Follow-up:** overrides, unused version keys, or decisions still open.
