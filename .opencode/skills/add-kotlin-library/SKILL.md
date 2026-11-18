---
name: Add Kotlin Library
description: Create a shared Kotlin/Spring library module under :lib:<name>
  for code used by multiple Spring Boot applications — mappers, exception
  types and advice, DTOs, common utilities. Registers include(":lib:<name>"),
  creates a java-library + Kotlin JVM build (no Boot plugin, no main),
  exports api/implementation correctly, wires it into consuming apps, and
  validates that it resolves and compiles. Use when extracting or adding
  shared code. Features stay inside applications; this skill creates
  libraries, not applications or feature modules.
---

# Add Kotlin Library

## Purpose

Create a reusable library module that several applications can depend on.
Gradle path and directory are grouped under `lib`:

```text
repository root
├── lib/
│   ├── common/       -> :lib:common
│   ├── exception/    -> :lib:exception
│   └── mapper/       -> :lib:mapper
├── shop-service/     -> :shop-service
├── billing-service/  -> :billing-service
└── settings.gradle.kts
```

Rules of the shape:

- **`:lib:<name>` is the Gradle path**, and `lib/<name>` is the directory.
  Never flatten a library to `:common` or place it at the repository root.
- **A library is not runnable.** No Spring Boot plugin, no `main`, no
  `application.yml`, no `bootJar`, no `developmentOnly`.
- **Applications depend on libraries.** A library must never depend on an
  application. Libraries may depend on other libraries as long as the
  graph stays acyclic.
- **Features stay inside applications.** Do not create `:lib:orders` for
  one app's feature; shared, app-agnostic code belongs here.

Since this repository uses Spring Boot, libraries may contain Spring
types (for example `@RestControllerAdvice` and `ProblemDetail`), but they
must not own runtime configuration or application bootstrap.

Templates live in `references/library-templates.md`; configuration rules
live in `references/dependency-configurations.md`.

## Project facts to confirm, not assume

1. Root `build.gradle.kts` — is the Kotlin plugin applied in
   `subprojects`, or per module? Is `java-library` applied anywhere? What
   toolchain is shared?
2. `settings.gradle.kts` — existing `:lib:*` entries, naming, and whether
   the `lib` container project already exists.
3. `gradle/libs.versions.toml` — version keys and aliases (`kotlin`,
   `spring-boot`, `spring-web`, `spring-boot-autoconfigure`, starters).
4. Existing libraries — package naming, `api` vs `implementation` usage,
   tests, auto-configuration approach.
5. Consuming applications — base packages, which apps need the library,
   and their test setup.

If the repository has no Kotlin build yet, read
`references/library-templates.md` and bootstrap the Kotlin plugin at the
root first (the application skill covers the same root change).

## Workflow

### 1. Define the library contract

- **Name** — kebab-case, concern-oriented (`common`, `exception`,
  `mapper`, `persistence`). One library per coherent concern.
- **Package** — `com.shopease.<name>` (`com.shopease.exception`).
- **Purpose** — what exactly is exported? Mappers? Exception types and
  advice? Shared DTOs? Utilities?
- **Spring awareness** — pure Kotlin, or does it use Spring annotations,
  `ProblemDetail`, Jackson, validation?
- **Consumers** — which applications will depend on it.
- **MapStruct/processors** — only if the project already uses them;
  otherwise use extension functions.

Do not extract "everything shared" into one large library. Start with the
smallest library that serves a real, shared concern.

### 2. Inspect and mirror

- Check for an existing library with the same purpose before adding one.
- Confirm the dependency direction: apps → libs, and libs → lower-level
  libs. No cycles.
- Match existing library package names, test style, and auto-config
  approach.
- If the code is used by only one application and has no clear future
  consumer, keep it in the app (`config/` or feature packages) instead of
  creating a library.

### 3. Register the library

Create the directory and add the nested project path:

```kotlin
include(":lib:common")
```

- Directory: `lib/common/`.
- The parent `lib` entry is a Gradle container project; it needs no
  `build.gradle.kts`.
- With type-safe project accessors, consumers can use
  `projects.lib.common`; otherwise use `project(":lib:common")`.

### 4. Create the library build file

Pure Kotlin library:

```kotlin
plugins {
    alias(libs.plugins.kotlin.jvm)
    `java-library`
}

dependencies {
    implementation(platform(libs.spring.boot.dependencies))

    testImplementation(libs.spring.boot.starter.test)
}
```

Spring-aware library (for example shared exception advice):

```kotlin
plugins {
    alias(libs.plugins.kotlin.jvm)
    `java-library`
}

dependencies {
    implementation(platform(libs.spring.boot.dependencies))

    api(libs.spring.web)
    api(libs.jackson.module.kotlin)
    compileOnly(libs.spring.boot.autoconfigure)

    testImplementation(libs.spring.boot.starter.test)
    testImplementation(libs.spring.boot.autoconfigure)
}
```

Rules:

- `java-library` is required so the module can use `api`.
- `api` only for types that appear in the library's public signatures
  (for example `ProblemDetail`, Jackson annotations on exported DTOs).
  Internal helpers are `implementation`.
- `compileOnly` for infrastructure the consuming Boot app provides; do
  not leak it to consumers. Repeat it at `testImplementation` when tests
  import those classes (for example `AutoConfigurations`).
- No Spring Boot plugin, `main`, `application.yml`, or `bootJar`. This is
  a library, not an application.
- BOM-managed artifacts stay versionless. Verify anything else with
  `scripts/verify-dependency.sh`.
- Do not add an application or another app's code as a dependency.
- Add processors only when needed: `ksp(...)` or `kapt(...)`, never
  `annotationProcessor` for Kotlin sources.
- Do not put application dependencies in the root build file.

### 5. Create the package layout

```text
lib/common/
├── build.gradle.kts
└── src/
    ├── main/kotlin/com/shopease/common/
    │   ├── ...
    └── test/kotlin/com/shopease/common/
        └── ...
```

Layouts by purpose:

```text
lib/exception/src/main/kotlin/com/shopease/exception/
├── ApiException.kt
├── NotFoundException.kt
├── ApiExceptionHandler.kt
└── ApiExceptionAutoConfiguration.kt

lib/exception/src/main/resources/META-INF/spring/
└── org.springframework.boot.autoconfigure.AutoConfiguration.imports

lib/mapper/src/main/kotlin/com/shopease/mapper/
└── MappingExtensions.kt

lib/common/src/main/kotlin/com/shopease/common/
├── util/
└── ...
```

Add only the packages the exports need.

### 6. Implement the shared concern

**Mappers** — prefer pure extension functions; they need no Spring
dependency. If the project uses MapStruct, put shared mapper
configuration/converters here and apply `kapt` with the MapStruct
processor. Do not move feature-specific mappers into the library.

**Exceptions** — define app-agnostic exception types (for example
`NotFoundException`, `ConflictException`) and, when needed, one
`@RestControllerAdvice` returning `ProblemDetail`. Do not import feature
exception types from applications: that would reverse the dependency
direction.

**Common** — utilities, value objects, constants, and shared DTOs with no
application-specific business rules.

**Spring components and auto-configuration.** Do not rely on component
scanning: the app's `@SpringBootApplication` lives in
`com.shopease.<app>` and will not scan a sibling `com.shopease.<lib>`
package. Expose beans through auto-configuration:

```kotlin
package com.shopease.exception

import org.springframework.boot.autoconfigure.AutoConfiguration
import org.springframework.context.annotation.Bean

@AutoConfiguration
class ApiExceptionAutoConfiguration {
    @Bean
    fun apiExceptionHandler() = ApiExceptionHandler()
}
```

`src/main/resources/META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`:

```text
com.shopease.exception.ApiExceptionAutoConfiguration
```

Alternatively document an explicit `@Import(ApiExceptionHandler::class)`
in the app when the project avoids auto-configuration. Never require an
app to widen `scanBasePackages`.

### 7. Wire it into the applications

In each app that needs it:

```kotlin
dependencies {
    implementation(project(":lib:exception"))
}
```

- Declare the library only in apps that use it.
- A library that exports another library's types may use `api(...)`;
  otherwise use `implementation(...)`.
- Runtime configuration and properties stay in the application.
- Never make a library depend on an app, and never create a cycle.

### 8. Validate — actually run these

```bash
./gradlew projects
./gradlew :lib:common:compileKotlin
./gradlew :lib:common:test
```

Then validate the consumers:

```bash
./gradlew :shop-service:compileKotlin
./gradlew :shop-service:test
```

- `projects` must show `:lib:common`.
- Compilation and tests pass with no `FAILED` resolutions.
- If the library contributes beans, the consuming app's context test must
  load without `@ComponentScan` changes.
- No app-to-library dependency runs in the wrong direction.

Do not report success for a step that was skipped or failed.

## Guardrails

- **Libraries, not applications.** No Boot plugin, `main`,
  `application.yml`, `bootJar`, or `developmentOnly`.
- **Naming is fixed by convention.** `:lib:<name>` and `lib/<name>`.
  Never create top-level `:common` or feature-named libraries.
- **No feature modules.** Features remain packages inside applications;
  this skill is for genuinely shared code.
- **Dependency direction is one-way.** Apps → libs → lower libs. A
  library must never reference an application.
- **`api` is deliberate.** Use it only for types in the public surface;
  everything else is `implementation`. Keep `java-library` applied.
- **No premature extraction.** One consumer with no clear reuse stays in
  the app.
- **No app-specific logic.** No app configuration, datasource, security
  setup, or feature endpoints in a shared library.
- **No scanning workarounds.** Use auto-configuration or explicit
  `@Import`; never broaden an app's component scan.
- **No guessed versions.** BOM-managed artifacts stay versionless; verify
  everything else.
- **No unrelated changes.** Adding a library must not alter existing
  applications except the explicit `project(...)` line in consumers.
- **No placeholder work.** Every exported class is used and every test
  asserts something real.

## Final response format

- **Library:** directory, Gradle path (`:lib:<name>`), package.
- **Build:** plugins, dependencies, `api` vs `implementation` choices,
  catalog entries added/reused.
- **Registration:** `settings.gradle.kts` change.
- **Contents:** exported classes and the concern they serve.
- **Consumers:** apps changed and the `project(...)` lines added.
- **Validation:** exact Gradle commands run and their result.
- **Follow-up:** auto-configuration, MapStruct, shared DTO decisions, or
  tests still to add.
