---
description: Add, remove, update, and validate Gradle version-catalog
  entries in gradle/libs.versions.toml, including versions, libraries,
  plugins, and bundles. Use when modifying Android or Kotlin Gradle
  dependencies.
name: gradle-version-catalog
---

# Gradle Version Catalog Manager

## Purpose

Safely manage the Gradle version catalog at `gradle/libs.versions.toml`
(or the catalog file explicitly configured by the project). Keep catalog
entries and their usages in Gradle build files consistent.

## Operating rules

1.  **Inspect before editing.**
    -   Find the actual version-catalog file. The conventional path is
        `libs.versions.toml`, but do not assume it if the project
        configures another catalog.
    -   Read the complete file and inspect relevant
        `settings.gradle(.kts)`, root/module `build.gradle(.kts)`, and
        convention-plugin files.
    -   Check the repository's existing naming, formatting, and alias
        conventions. Follow them.
2.  **Make the smallest safe change.** Preserve comments, ordering,
    blank lines, quote style, and unrelated entries. Do not rewrite the
    entire TOML file just to change one entry.
3.  **Do not guess versions.** Use a version explicitly supplied by the
    user or already established in the project. If the user asks for the
    latest version, verify it from an authoritative source (prefer the
    library/plugin's official release page or repository). If it cannot
    be verified, ask the user rather than inventing a version.
4.  **Avoid duplicate aliases.** Before adding an entry, check for an
    existing alias, module coordinate, plugin ID, or equivalent
    declaration. Reuse or update the existing entry when appropriate.
5.  **Respect references.** Before removing or renaming an alias or
    version key, search the whole repository for usages, including
    `build.gradle.kts`, `build.gradle`, convention plugins, included
    builds, and build logic. Update references only when the user
    requested that change and the mapping is unambiguous.
6.  **Do not perform unrelated upgrades or cleanup.** Never change
    unrelated dependencies, plugin versions, repositories, or build
    configuration.
7.  **Validate the result.** Check TOML syntax and inspect the diff. If
    practical, run the relevant Gradle task (for example
    `./gradlew help` or the project's requested build task). Do not
    claim validation passed unless it actually ran successfully.
8.  **Report clearly.** Summarize entries added, changed, or removed;
    list affected build-file references; mention validation performed
    and any remaining risks.

## Supported TOML sections

Work with the sections that already exist, adding a section only when
needed:

-   `[versions]` --- reusable version strings.
-   `[libraries]` --- module dependencies.
-   `[plugins]` --- Gradle plugins.
-   `[bundles]` --- groups of library aliases.

Use Gradle version-catalog syntax. Prefer a shared version key when
multiple related dependencies use the same version and the project
convention supports it.

## Add a version

When asked to add a version:

1.  Check whether the key already exists.
2.  If it exists with the requested value, report that no change is
    needed.
3.  If it exists with a different value, treat this as an update and
    check all references before changing it.
4.  Add the key under `[versions]` using the project's alias style.

Example:

``` toml
[versions]
kotlin = "2.1.20"
```

Do not add a version key that is not used by a library or plugin unless
the user explicitly asks for a standalone version entry.

## Add a library

1.  Identify the Maven coordinates (`group:artifact`) and the requested
    version or existing version reference.
2.  Check for an existing matching library declaration.
3.  Add or reuse a version key in `[versions]` when appropriate.
4.  Add the alias under `[libraries]`.
5.  If the user asked to wire the dependency into a module, add the
    corresponding `implementation(libs.alias)`, `api(libs.alias)`,
    `testImplementation(libs.alias)`, or other explicitly requested
    configuration to the correct build file. Do not modify build files
    when the request is only to update the catalog.

Example:

``` toml
[versions]
okhttp = "4.12.0"

[libraries]
okhttp = { module = "com.squareup.okhttp3:okhttp", version.ref = "okhttp" }
```

A direct version is also valid when that matches the project's
convention:

``` toml
[libraries]
example = { module = "com.example:example", version = "1.2.3" }
```

## Add a plugin

1.  Identify the plugin alias, plugin ID, and version.
2.  Check for existing plugin declarations and aliases.
3.  Add/reuse the version key when appropriate.
4.  Add the plugin under `[plugins]`.

Example:

``` toml
[versions]
android-gradle = "8.8.2"

[plugins]
android-application = { id = "com.android.application", version.ref = "android-gradle" }
```

Only update `plugins { alias(libs.plugins...) }` in build files if the
user asked to apply the plugin.

## Remove a library or plugin

1.  Find the exact alias requested and confirm what it maps to.
2.  Search all project files for references to that alias (including
    generated or convention build logic where applicable).
3.  If references remain, **do not leave the project broken**:
    -   Explain which files still use the alias.
    -   Ask whether the user wants those usages removed/replaced, or
        keep the catalog entry.
    -   Do not silently delete usages or substitute a different
        dependency.
4.  If no references remain, remove only the requested entry.
5.  Check whether its version key is now unused. Remove that version key
    only if no other library/plugin refers to it and the user requested
    cleanup or has clearly asked to remove the unused associated
    version. Otherwise leave it and report it as unused.
6.  Check bundles for references to a removed library alias. Update a
    bundle only as part of the requested removal and only when the
    intended result is clear; otherwise ask.

## Remove or update a version

A version key may be referenced by multiple libraries or plugins.

-   Before removing a version key, search for every `version.ref` that
    points to it.
-   If any references remain, do not delete the key. Explain the
    dependent aliases and ask whether they should be migrated or
    removed.
-   Before changing a version value, identify all dependencies/plugins
    affected and report the scope. Apply the requested change
    consistently; do not split versions unless requested.
-   Never remove a version merely because its key name looks unused.
    Confirm actual references first.

## Rename an alias

Treat a rename as a coordinated migration:

1.  Search for all usages of the old alias.
2.  Add the new alias with the same coordinates/version.
3.  Update all unambiguous usages to the new generated accessor.
4.  Remove the old alias only after confirming no references remain.
5.  Check bundles and convention plugins for old references.

If the requested rename could change dependency behavior, ask before
editing.

## Alias and accessor conventions

-   Prefer the project's existing alias style (for example
    `androidx-core-ktx`, `androidxCoreKtx`, or another established
    pattern).
-   Remember that Gradle converts catalog aliases into type-safe
    accessors. Hyphens, underscores, and dots can create accessor
    nesting; inspect existing usage patterns and use the correct
    accessor in build scripts.
-   Use lowercase, descriptive aliases where consistent with the
    project.
-   Do not create two aliases for the same module unless the project
    intentionally needs distinct versions or configurations.

## TOML safety checks

After editing, verify:

-   Every `version.ref` points to an existing key in `[versions]`.
-   Every bundle member points to an existing alias in `[libraries]`.
-   Library entries have valid module coordinates or valid `group` and
    `name` fields.
-   Plugin entries have an `id` and a valid version declaration (unless
    the project's Gradle setup intentionally supplies it elsewhere).
-   No duplicate keys exist within a TOML table.
-   Quotes, braces, commas, and table headers are valid TOML.
-   All changed aliases match their build-file accessors.

Do not claim that TOML or Gradle validation succeeded based only on
visual inspection.

## Interaction policy

Proceed without asking follow-up questions when the request, target
alias, and version/coordinates are clear.

Ask one concise question when a required value is missing, multiple
entries match, a removal would break existing references, or the
requested operation could have unintended effects. For destructive
changes, explain the affected references before proceeding.

## Final response format

After the task, provide a concise report:

-   **Catalog file:** path changed.
-   **Changes:** aliases/versions/plugins/bundles added, updated, or
    removed.
-   **Usages:** build files changed, or remaining references that
    prevented removal.
-   **Validation:** checks and Gradle commands actually run, including
    failures.
-   **Follow-up:** any unused version keys or unresolved decisions.
