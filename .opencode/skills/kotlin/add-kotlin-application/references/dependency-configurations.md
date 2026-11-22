# Application build configurations

Each application is self-contained. Choose the narrowest configuration
that works and declare only what the generated code uses.

| Configuration        | Needs                       | Runtime | Compile consumers | Use for |
| -------------------- | --------------------------- | ------- | ----------------- | ------- |
| `implementation`     | Kotlin JVM                  | yes     | no                | Default for all application code |
| `compileOnly`        | Kotlin JVM                  | no      | no                | Compile-only annotations/APIs |
| `runtimeOnly`        | Kotlin JVM                  | yes     | no                | JDBC drivers, logging backends |
| `ksp`                | Kotlin JVM + KSP plugin     | no      | no                | Kotlin processors with KSP support |
| `kapt`               | Kotlin JVM + `kotlin-kapt`  | no      | no                | Processors without KSP support |
| `testImplementation` | Kotlin JVM                  | no      | no                | JUnit, AssertJ, Mockito, slice tests |
| `testRuntimeOnly`    | Kotlin JVM                  | no      | no                | Engines/fixtures needed only to run tests |
| `developmentOnly`    | Spring Boot plugin          | no      | no                | DevTools and dev-time tooling |

`api` is not used: an application is not a library and nothing consumes
it. `annotationProcessor` only reaches `javac`, so use `ksp`/`kapt` for
Kotlin sources.

## Rules for generated applications

1. **One app, one Gradle module.** Features are packages inside it.
   Never add a `build.gradle.kts` for a feature.
2. **Use `implementation` everywhere.** Do not apply `java-library` and
   do not use `api`.
3. **The app owns the Spring Boot setup.** Boot plugin, `main`,
   `application.yml`, `developmentOnly`, migrations, and packaging belong
   to the app module, never the root.
4. **No app-to-app dependencies.** Two applications in the same build do
   not depend on each other. Shared mappers, exception types/advice,
   DTOs, and utilities go in `:lib:<name>` modules; app-specific
   infrastructure goes in `config/`.
5. **Processors are not runtime dependencies.** Declare them under `ksp`
   or `kapt`; never under `implementation`. Prefer KSP when supported,
   and never wire one processor through both.
6. **BOM entries stay versionless.** Starters, `kotlin-reflect`,
   `jackson-module-kotlin`, and DevTools are managed by
   `spring-boot-dependencies`. Only non-managed libraries get a version.
7. **One `platform(...)` per application build file.** Add the BOM where
   the dependencies are declared; do not assume the root provides it.
8. **No dependencies at the root.** Root configures plugins, toolchain,
   repositories, and test platform only.
9. **No speculative dependencies.** Generate the code first; add only
   what it imports.

## Kotlin specifics

- The Kotlin plugin supplies `kotlin-stdlib`; never declare it.
- Keep the Kotlin plugin version aligned with the BOM's managed Kotlin
  version (`scripts/verify-dependency.sh org.jetbrains.kotlin:kotlin-stdlib`
  → `managed_version`). Do not use a newer standalone Kotlin release for
  a new application.
- `kotlin-spring` opens Spring-annotated classes for proxying.
  `kotlin-jpa` adds the no-arg constructor for entities. Apply each only
  where needed.
- `jvmToolchain(...)` configures Java and Kotlin together. Do not add an
  app-local `jvmTarget` that can drift from the root toolchain.
- Kotlin Multiplatform libraries use the base coordinate
  (`kotlinx-coroutines-core`); Gradle selects the `-jvm` variant.

## Version checks for a new application

```bash
scripts/verify-dependency.sh <group:artifact>
scripts/verify-dependency.sh <group:artifact> <version>
```

- `managed=true` → no version in the catalog.
- `managed=false` → version or `version.ref` required.
- Use `latest_stable`, not `latest_release` (which may be an RC).
- `kotlin_compatibility=review` means the library was built with a newer
  Kotlin than the catalog; do not bump Kotlin silently — report it.
- Never guess a version, and never add an RC/milestone without an
  explicit request.

## Typical application stacks

| Application kind    | Dependencies |
| ------------------- | ------------ |
| REST + JPA          | webmvc, validation, data-jpa, `kotlin-reflect`, `jackson-module-kotlin`, webmvc-test, data-jpa-test |
| REST only           | webmvc, validation, `kotlin-reflect`, `jackson-module-kotlin`, webmvc-test |
| Persistence only    | data-jpa, `kotlin-reflect`, data-jpa-test; add the base test starter if missing |
| Integration/worker  | the client/messaging dependency the code uses, base test starter |

On Spring Boot 4, `spring-boot-starter-web` is deprecated in favor of
`spring-boot-starter-webmvc`, and `@WebMvcTest`/`@DataJpaTest` need
their own slice-test starters. On Spring Boot 3.x, use the legacy names.

## Multiple applications in one build

- Each app declares its own catalog dependencies and BOM platform.
- Each app has a unique `spring.application.name`, `server.port`, and
  datasource/schema.
- No `project(...)` dependencies between apps.
- Adding a new app never changes an existing app's build file.
