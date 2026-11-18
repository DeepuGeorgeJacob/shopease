# Choosing the right configuration

The configuration decides who sees the library at compile time, at
runtime, and transitively. Picking the narrowest one that works keeps the
module graph honest.

| Configuration            | Needs plugin   | On consumer runtime | Exposed to consumers at compile time | Use for |
| ------------------------ | -------------- | ------------------- | ------------------------------------ | ------- |
| `api`                    | `java-library` | yes                 | yes                                  | Types from the library appear in this module's public API (method params/returns, public supertypes) |
| `implementation`         | any Java       | yes                 | no                                   | Everything else — the default for feature internals |
| `compileOnly`            | any Java       | no                  | no                                   | Annotations and APIs used only at compile time (e.g. `@Nullable`, Lombok-style tooling) |
| `annotationProcessor`    | any Java       | no                  | no                                   | Code generators run by `javac` |
| `runtimeOnly`            | any Java       | yes                 | no                                   | JDBC drivers, logging backends, template engines |
| `testImplementation`     | any Java       | no                  | no                                   | JUnit, AssertJ, Mockito, test slices |
| `testRuntimeOnly`        | any Java       | no                  | no                                   | Engines/fixtures needed only to run tests |
| `developmentOnly`        | Spring Boot    | no                  | no                                   | Dev-time tooling excluded from the boot jar, e.g. Docker Compose support |

## Decision rules

1. **Start with `implementation`.** Promote to `api` only when the library
   type is unavoidable in the module's public signatures. `api` leaks the
   dependency to every downstream module and makes future replacement
   expensive.
2. **Feature modules should be `java-library`.** This is what makes `api`
   available at all. A module applying only `java` cannot use `api`.
3. **The Spring Boot app module owns `developmentOnly`.** Feature modules
   should not pull dev tooling.
4. **One dependency, one place.** If two modules need the same library,
   either both declare it (fine for `implementation` internals) or the
   owning module exports it with `api` — never copy classes around to
   avoid the dependency.
5. **Never put a dependency in the root build file.** Root applies plugins
   with `apply false` and configures shared `subprojects` settings only.
6. **`platform(...)` goes where the dependencies are declared.** The BOM
   `platform(libs.spring.boot.dependencies)` belongs in the module that
   uses versionless BOM-managed entries, not necessarily at the root.

## BOM-managed vs explicit versions

- Spring Boot starters, Jackson, Hibernate, Tomcat, JUnit, Mockito, and
  anything else listed in `spring-boot-dependencies` are managed: declare
  the catalog entry **without** a version and let the BOM decide.
- Libraries outside the BOM need an explicit version in the catalog.
- If you must deviate from the BOM for one artifact, prefer a
  `constraints`/`platform` override in the module over a hardcoded
  version, and tell the user which BOM version you are overriding.

## Version selection

- Newest stable release unless the user pins something.
- Never `-SNAPSHOT`, `-alpha`, `-beta`, `-M*`, or `-RC*` without an
  explicit request.
- A version must exist on Maven Central before it enters the catalog —
  `scripts/verify-dependency.sh` proves this.
