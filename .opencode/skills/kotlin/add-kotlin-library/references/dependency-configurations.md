# Library build configurations

A library is consumed by applications, so the configuration choice decides
what consumers can compile against. Apply `java-library` and pick the
narrowest configuration that exposes exactly the public surface.

| Configuration        | Runtime | Consumer compile | Use for |
| -------------------- | ------- | ---------------- | ------- |
| `api`                | yes     | yes              | Types in this library's public signatures |
| `implementation`     | yes     | no               | Internal helpers and details |
| `compileOnly`        | no      | no               | Annotations/APIs the consuming app provides (e.g. `@AutoConfiguration`) |
| `runtimeOnly`        | yes     | no               | JDBC drivers, logging backends |
| `ksp`                | no      | no               | Kotlin processors with KSP support |
| `kapt`               | no      | no               | Processors without KSP support |
| `testImplementation` | no      | no               | JUnit, AssertJ, Mockito, `ApplicationContextRunner` |
| `testRuntimeOnly`    | no      | no               | Engines/fixtures needed only to run tests |

`api` requires `java-library`; without it Gradle rejects the configuration.
`annotationProcessor` only reaches `javac`, so never use it for Kotlin
sources — use `ksp`/`kapt`.

## Rules for generated libraries

1. **`lib/<name>` and `:lib:<name>`.** Register
   `include(":lib:<name>")`; `lib/` is a container project with no build
   file. Never create a top-level `:common` library.
2. **Libraries are not runnable.** No Spring Boot plugin, `main`,
   `application.yml`, `bootJar`, or `developmentOnly`.
3. **`api` is deliberate.** Export only types that appear in public
   signatures (`ProblemDetail`, exported DTO annotations). Everything else
   is `implementation`.
4. **`compileOnly` for app-provided infrastructure.** Libraries that
   declare auto-configuration use `compileOnly` for
   `spring-boot-autoconfigure`; the app supplies it at runtime.
5. **One-way dependencies.** Apps → `:lib:*` → lower `:lib:*`. A library
   must never depend on an application, and the graph stays acyclic.
6. **No feature modules.** Features stay packages inside applications.
   This module exists only for code genuinely shared by multiple apps.
7. **No app-specific logic.** No datasource, security config, feature
   endpoints, ports, or application properties in a library.
8. **BOM entries stay versionless.** Starters, `spring-web`,
   `spring-boot-autoconfigure`, `jackson-module-kotlin`, and
   `jakarta.validation-api` are managed by `spring-boot-dependencies`.
   Verify anything else with `scripts/verify-dependency.sh`.
9. **One `platform(...)` per library build file.** Add the BOM where the
   dependencies are declared; do not assume the root provides it.
10. **No dependencies at the root.** The root configures plugins,
    toolchain, repositories, and test platform only.

## Kotlin specifics

- The Kotlin plugin supplies `kotlin-stdlib`; never declare it.
- Keep the Kotlin plugin version aligned with the BOM's managed Kotlin
  version (`scripts/verify-dependency.sh org.jetbrains.kotlin:kotlin-stdlib`
  → `managed_version`).
- A library does not need `kotlin-spring` or `kotlin-jpa` unless it
  contains proxied Spring components or JPA entities. Shared advice classes
  are instantiated directly and do not need all-open.
- `jvmToolchain(...)` comes from the root; do not add a library-local
  `jvmTarget` that can drift.
- Kotlin Multiplatform dependencies use the base coordinate; Gradle
  selects the `-jvm` variant.

## Version checks for a new library

```bash
scripts/verify-dependency.sh <group:artifact>
scripts/verify-dependency.sh <group:artifact> <version>
```

- `managed=true` → no version in the catalog.
- `managed=false` → version or `version.ref` required.
- Use `latest_stable`, not `latest_release` (which may be an RC).
- `kotlin_compatibility=review` means the library was built with a newer
  Kotlin than the catalog; do not bump Kotlin silently — report it.
- Never guess a version, and never add an RC/milestone without an explicit
  request.

## Typical library stacks

| Library kind             | Dependencies |
| ------------------------ | ------------ |
| Utilities/constants      | Kotlin JVM + `java-library`; `testImplementation` base test starter |
| Mapping helpers          | same as utilities |
| Exception types + advice | `api` `spring-web`; `compileOnly` `spring-boot-autoconfigure`; test starter |
| Shared DTOs with Jackson | `api` `jackson-module-kotlin` (and `spring-web` if `ProblemDetail`/HTTP types appear) |
| Shared DTOs with validation | `api` `jakarta.validation-api` |
| Auto-configuration       | `compileOnly` `spring-boot-autoconfigure`; test starter for `ApplicationContextRunner` |
| MapStruct mappers        | MapStruct at `implementation` + `kapt` processor, only if the project already uses MapStruct |

On Spring Boot 4, prefer individual managed modules such as `spring-web`
over `spring-boot-starter-web`. On Spring Boot 3.x the same coordinates
apply; only the Boot-managed versions change.

## Consuming libraries from applications

```kotlin
dependencies {
    implementation(project(":lib:exception"))
    implementation(project(":lib:common"))
}
```

- Declare a library only in apps that use it.
- Use `implementation(project(...))` (or `api` inside another library that
  re-exports the types).
- Adding a library must not require the app to widen `scanBasePackages`;
  expose beans through auto-configuration or an explicit `@Import`.
- Each app still owns its BOM platform, configuration, migrations, and
  runtime dependencies.
