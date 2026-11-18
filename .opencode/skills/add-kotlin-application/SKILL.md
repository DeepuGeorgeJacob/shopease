---
name: Add Kotlin Application
description: Scaffold a new Spring Boot Kotlin application under the
  repository root in a Gradle multi-module build. Registers it in settings,
  creates its build file and catalog entries, entry point and configuration,
  package-by-feature layout inside the app (controller/service/repository/
  entity/DTO per feature), tests, and validates that it builds and boots.
  Use when creating a new application. Features are packages inside the
  application; shared code goes in `:lib:<name>` modules.
---

# Add Kotlin Application

## Purpose

Create a new, independently runnable Spring Boot Kotlin application. One
application is one Gradle module, one `main` class, one `application.yml`,
and one `bootJar`.

```text
repository root
├── app-one/          <- one application
├── app-two/          <- another application
└── settings.gradle.kts
```

Inside each application, features are ordinary packages:

```text
app-one/src/main/kotlin/com/shopease/appone/
├── AppOneApplication.kt
├── config/
└── orders/           <- a feature
    ├── controller/
    ├── service/
    ├── repository/
    ├── entity/
    ├── dto/
    └── mapper/
```

Rules of the shape:

- **Features are packages inside the application.** They have no Gradle
  path, no `build.gradle.kts`, and no `settings.gradle.kts` entry.
- **Applications are siblings.** Each app owns its own Boot plugin,
  dependencies, configuration, migrations, and tests. One app must not
  depend on another app.
- **Shared code lives in libraries.** Mappers, exception types/advice,
  DTOs, and common utilities used by more than one app belong in
  `:lib:<name>` modules created with the `add-kotlin-library` skill. Do
  not copy shared code between apps.
- **This skill is only for new applications.** It is not the workflow for
  adding a dependency to an existing app (edit the catalog/build file
  directly) and not for creating shared libraries.

Templates live in `references/application-templates.md`. Build
configuration rules live in
`references/dependency-configurations.md`. Shared mappers, exceptions,
and utilities are created with the `add-kotlin-library` skill and consumed
as `implementation(project(":lib:<name>"))`.

## Project facts to confirm, not assume

Read these before writing anything.

1. Root `build.gradle.kts` — is the Kotlin plugin applied once in
   `subprojects`, or does each app apply it? What toolchain is shared?
   Is the Spring Boot plugin declared `apply false`? The root must never
   gain application dependencies.
2. `settings.gradle.kts` — application names (`:app-one`), include style,
   and grouping.
3. `gradle/libs.versions.toml` — existing alias style and version keys
   (`kotlin`, `spring-boot`), starter aliases, and plugin aliases
   (`kotlin-jvm`, `kotlin-spring`, `kotlin-jpa`, `ksp`). Note the Boot
   major version: it decides starter names and test-slice packages.
4. Existing applications — base package convention
   (`com.shopease.<app>`), feature package layout, DTO/mapper style,
   exception handling, test style, persistence/migration stack, ports.
5. `application.yml` ownership and profile conventions.

If no Kotlin application exists yet, use **Bootstrap mode** below.

## Workflow

### 1. Define the application contract

Ask only for values you cannot infer; otherwise state your assumptions.

- **Name** — kebab-case directory/Gradle name (`shop-service`).
- **Base package** — `com.shopease.<packagesafe>` (`com.shopease.shop`).
- **Port** — must not collide with other apps in the repository.
- **Persistence** — does the app own a database? Which one?
- **Initial features** — one or more feature packages (for example
  `orders`, `billing`) with their endpoints.
- **Integrations** — security, messaging, scheduling, clients (do not add
  unless requested).
- **Migrations** — Flyway/Liquibase? Centralized in this app?
- **Build scope** — included in this repository's Gradle build.

Defaults when unspecified: one web app, no persistence, one example
feature slice, no new infrastructure.

### 2. Inspect and mirror

- Find the closest existing application and copy its conventions:
  package structure, DTO suffixes, mappers, exception handling, test
  setup, config layout. Do not invent a second style.
- Confirm no existing app already covers the same responsibility.
- Confirm the base package and port are unique across the repository.
- Never create extra Gradle modules to mirror another app's structure;
  copy its package layout inside the new app instead.

### 3. Register the application

Add it to `settings.gradle.kts`, matching the existing include style and
ordering:

```kotlin
include(":shop-service")
```

Do not create a separate Gradle build unless the user explicitly asks for
a standalone project outside this build.

### 4. Create the application build file and catalog entries

```kotlin
plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.kotlin.jpa)
    alias(libs.plugins.spring.boot)
}

dependencies {
    implementation(platform(libs.spring.boot.dependencies))

    implementation(libs.spring.boot.starter.webmvc)
    implementation(libs.spring.boot.starter.data.jpa)
    implementation(libs.spring.boot.starter.validation)
    implementation(libs.kotlin.reflect)
    implementation(libs.jackson.module.kotlin)

    developmentOnly(libs.spring.boot.devtools)
    testImplementation(libs.spring.boot.starter.webmvc.test)
    testImplementation(libs.spring.boot.starter.data.jpa.test)
}
```

Rules:

- An application is not a library: no `java-library`, no `api`, no
  cross-app `project(...)` dependencies. Use `implementation`. The only
  allowed `project(...)` lines point at `:lib:<name>` shared libraries.
- Remove plugin lines the root already applies and drop dependencies the
  app does not use (for example `data-jpa` and `kotlin-jpa` for an app
  without persistence).
- Starters and other BOM-managed artifacts are versionless. Add a version
  only when `scripts/verify-dependency.sh <group:artifact>` reports
  `managed=false`; never guess.
- Spring Boot 4 renamed the MVC starter: use
  `spring-boot-starter-webmvc` (`spring-boot-starter-web` is deprecated
  but still works). Slice-test support comes from
  `spring-boot-starter-webmvc-test` and
  `spring-boot-starter-data-jpa-test`, not from the base test starter.
- The app owns `developmentOnly`, `application.yml`, and the Boot plugin.
- Add new catalog aliases only when missing, following the existing alias
  style.

### 5. Create the application skeleton

```text
shop-service/
├── build.gradle.kts
└── src/
    ├── main/kotlin/com/shopease/shop/
    │   ├── ShopServiceApplication.kt
    │   ├── config/
    │   └── orders/                 <- a feature package
    │       ├── controller/
    │       ├── service/
    │       ├── repository/
    │       ├── entity/
    │       ├── dto/
    │       ├── mapper/
    │       └── exception/
    ├── main/resources/
    │   └── application.yml
    └── test/kotlin/com/shopease/shop/
        ├── ShopServiceApplicationTests.kt
        └── orders/
            ├── service/OrdersServiceTest.kt
            └── controller/OrdersControllerTest.kt
```

- Feature packages are named for the business capability (`orders`,
  `billing`, `catalog`), not `feature-a`, once the domain is known.
- Add only the layer packages the feature uses. No persistence means no
  `entity`/`repository`; no custom mapping means no `mapper`.
- App-specific infrastructure (security, Jackson, clock configuration)
  goes in `config/`. Code shared with another application (mappers,
  exception types/advice, DTOs, utilities) belongs in a `:lib:<name>`
  module, not in a `common/` package and not in the app build.

### 6. Implement the first feature slice

Use the templates in `references/application-templates.md`, then adapt
names.

- **Controller** — thin, `@RestController`, constructor injection,
  `@Valid` on request bodies, returns DTOs. Never returns entities.
- **Service** — owns transaction boundaries (`@Transactional` on writes,
  `readOnly = true` at class level), throws domain exceptions, no HTTP
  types.
- **Repository** — Spring Data interface for JPA, or the project's
  existing adapter pattern. No repository when there is no persistence.
- **Entity** — a normal class, not a `data class`; nullable generated id;
  `kotlin-jpa` supplies the no-arg constructor. Do not expose it from the
  API layer.
- **DTOs** — `data class` request/response models; Bean Validation
  annotations use `@field:` targets.
- **Mapper** — feature-specific mapping stays in the feature package as
  extension functions; MapStruct only if the project already uses it
  (then `kapt`). Mappers shared by multiple apps belong in `:lib:<name>`.
- **Exceptions** — define the feature exception under the feature package
  and map it in the app's advice. App-agnostic exception types and the
  shared `ProblemDetail` advice belong in `:lib:<name>` (see
  `add-kotlin-library`). Never register two advices for the same
  exception type.

Features are peers inside one application. If two features need the same
code, move it to `config/` (app-specific infrastructure) or to a
`:lib:<name>` module (shared with other apps). Never create a Gradle
module per feature.

If the request is only for the application shell, stop after the
skeleton, configuration, and context test, and list the feature slices as
follow-up.

### 7. Configure the application

- Create `application.yml` with a unique app name and port:
  `spring.application.name` and `server.port`.
- Add datasource/JPA/pool settings only when the app actually uses a
  database. Do not invent credentials; follow the project's env-var
  convention.
- Own migrations in this app (`src/main/resources/db/migration` for
  Flyway) unless the repository already centralizes them elsewhere.
- Add profiles (`application-local.yml`, etc.) only if the repository
  uses them.
- Never enable `spring.jpa.hibernate.ddl-auto=update` in place of
  migrations.

### 8. Generate real tests

- **Application** — context-load test using the app's main class. This is
  the cheapest proof the new application wires correctly.
- **Service unit test** — Mockito or the project's existing mocking
  library; assert behavior, not getters.
- **Controller slice** — `@WebMvcTest(OrderController::class)` from
  `org.springframework.boot.webmvc.test.autoconfigure`, with
  `@MockitoBean` for the service and MockMvc for status/body assertions.
  The app's own `@SpringBootApplication` satisfies the slice test; no
  test-only application class is needed.
- **Repository** — `@DataJpaTest` from
  `org.springframework.boot.data.jpa.test.autoconfigure`, with
  `spring-boot-starter-data-jpa-test`, only when the project already
  provides an embedded database or Testcontainers setup. Do not add H2 or
  Testcontainers just to satisfy a scaffold; report it as follow-up.
- On Spring Boot 3.x, the legacy slice packages still apply:
  `org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest`
  and `org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest`.

Do not leave empty test bodies, `TODO()` placeholders, or tests that only
assert `true`.

### 9. Validate — actually run these

```bash
./gradlew projects
./gradlew :shop-service:compileKotlin
./gradlew :shop-service:test
./gradlew :shop-service:bootJar
```

Optionally smoke-test startup if the user asked:

```bash
./gradlew :shop-service:bootRun
```

Stop it once startup succeeds, and confirm the configured port.

- `projects` must list the new application.
- Compilation and tests must pass with no `FAILED` resolutions.
- The app must have no `project(...)` dependency on another application.
- If the app context fails, fix the wiring/config rather than disabling
  the test.

Do not report success for a step that was skipped or failed.

## Bootstrap mode (no Kotlin application yet)

Use this when the repository has no Kotlin/Spring Boot application, or the
root still applies only `java`.

1. **Pick the Kotlin version from the BOM, not from "latest".** The Spring
   Boot BOM imports `kotlin-bom`; the Kotlin Gradle plugin and stdlib must
   match it:

   ```bash
   scripts/verify-dependency.sh org.jetbrains.kotlin:kotlin-stdlib
   ```

   Use the reported `managed_version` for the catalog's `kotlin` key. Do
   not substitute `latest_stable` when the two differ.

2. **Add the catalog entries** the new application needs (see
   `references/application-templates.md`): `kotlin` version, plugin
   aliases, and starter/Kotlin support aliases.

3. **Update the root build** to apply the Kotlin JVM plugin and Java
   toolchain consistently. Do not apply `java-library`, keep the Spring
   Boot plugin `apply false`, and keep `dependencies { }` out of the root.
   The target shape is in the templates.

4. **Create the application** and validate it with
   `./gradlew projects` and `./gradlew :<app>:test` before adding more
   features.

## Guardrails

- **Applications only.** Do not create Gradle modules for features.
  Features are packages inside the app. Reusable mappers, exception
  types/advice, DTOs, and utilities go in `:lib:<name>` modules created
  with the `add-kotlin-library` skill.
- **One app per Gradle module.** No app depends on another app. Sharing
  happens through `:lib:<name>` libraries or an explicit future refactor
  the user requests.
- **The app owns its Spring Boot setup.** Boot plugin, `main`,
  `application.yml`, `developmentOnly`, migrations, and packaging belong
  to the app module, never the root.
- **No `java-library`/`api`.** Applications use `implementation`.
- **Unique identity.** Base package, Gradle name, port, and datasource
  must not collide with an existing app.
- **No guessed versions.** BOM-managed artifacts stay versionless; verify
  everything else.
- **No unrelated changes.** Do not modify existing applications or the
  root build beyond what the new app requires.
- **No invented conventions.** Mirror the closest existing application.
- **No entity leakage.** Controllers expose DTOs, not JPA entities.
- **No infrastructure without a requirement.** Do not add security,
  messaging, caching, Docker, or migration tooling unless asked.
- **No placeholder work.** Every generated class is used and every test
  asserts something real.
- **Never leave the build broken.** If a template dependency cannot be
  resolved, stop and report it.

## Final response format

- **Application:** directory, Gradle name, base package, port.
- **Build:** plugins applied, dependencies added, catalog entries
  added/reused.
- **Registration:** `settings.gradle.kts` change.
- **Features:** feature packages created and their layers.
- **Files:** created tree.
- **Validation:** exact Gradle commands run and their result.
- **Follow-up:** migrations, repository tests, config keys, security,
  conventions still to confirm, and shared code that should move to a
  `:lib:<name>` library.
