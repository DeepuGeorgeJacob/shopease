# Kotlin library module templates

A shared library lives at `lib/<name>` and is included as `:lib:<name>`.
Adapt names and remove anything the library does not export.

Examples use `:lib:common`, `:lib:exception`, and `:lib:mapper`.

## 1. Registration

```kotlin
rootProject.name = "shopease"

include(":shop-service")
include(":lib:common")
include(":lib:exception")
include(":lib:mapper")
```

- `lib/` is a Gradle container project. It does not need a build file.
- Consumers use `project(":lib:common")`, or `projects.lib.common` when
  type-safe project accessors are enabled.
- Never include `lib` itself as a project.

## 2. Catalog entries

Add only what the libraries use. All of these are BOM-managed, so they
carry no version:

```toml
[libraries]
spring-web = { module = "org.springframework:spring-web" }
spring-boot-autoconfigure = { module = "org.springframework.boot:spring-boot-autoconfigure" }
spring-boot-starter-test = { module = "org.springframework.boot:spring-boot-starter-test" }
jackson-module-kotlin = { module = "com.fasterxml.jackson.module:jackson-module-kotlin" }
jakarta-validation-api = { module = "jakarta.validation:jakarta.validation-api" }
```

`jackson-module-kotlin` and `jakarta-validation-api` are added only when
the library exports types that need them. `spring-boot-starter-test` and
`spring-boot-autoconfigure` are also BOM-managed. Verify any non-managed
dependency with `scripts/verify-dependency.sh <group:artifact>` before
adding it.

## 3. Pure Kotlin library build file

For utilities, constants, or mapping helpers:

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

The BOM is present only to version test dependencies; remove it if the
project uses a different test version source.

## 4. Spring-aware library build file

For shared exception types and advice:

```kotlin
plugins {
    alias(libs.plugins.kotlin.jvm)
    `java-library`
}

dependencies {
    implementation(platform(libs.spring.boot.dependencies))

    api(libs.spring.web)
    compileOnly(libs.spring.boot.autoconfigure)

    testImplementation(libs.spring.boot.starter.test)
    testImplementation(libs.spring.boot.autoconfigure)
}
```

- `api(libs.spring.web)` because `ProblemDetail` and `HttpStatus` appear
  in public signatures.
- `compileOnly(libs.spring.boot.autoconfigure)` for
  `@AutoConfiguration`; the Boot application supplies it at runtime.
- `testImplementation(libs.spring.boot.autoconfigure)` because
  `ApplicationContextRunner` tests import `AutoConfigurations`, which
  `compileOnly` does not put on the test compile classpath.
- Add `api(libs.jackson.module.kotlin)` only when exported DTOs carry
  Jackson annotations.
- Add `api(libs.jakarta.validation.api)` only when exported DTOs use
  Bean Validation.

Never add `spring-boot-starter-web` or another starter to a library
unless the library genuinely needs the whole starter; prefer the
individual managed modules.

## 5. Common utilities library

`lib/common/src/main/kotlin/com/shopease/common/util/Numbers.kt`

```kotlin
package com.shopease.common.util

fun requirePositive(value: Long, name: String): Long {
    require(value > 0) { "$name must be positive" }
    return value
}
```

`lib/common/src/test/kotlin/com/shopease/common/util/NumbersTest.kt`

```kotlin
package com.shopease.common.util

import org.assertj.core.api.Assertions.assertThat
import org.assertj.core.api.Assertions.assertThatThrownBy
import org.junit.jupiter.api.Test

class NumbersTest {
    @Test
    fun `returns a positive value`() {
        assertThat(requirePositive(5, "id")).isEqualTo(5)
    }

    @Test
    fun `rejects zero`() {
        assertThatThrownBy { requirePositive(0, "id") }
            .isInstanceOf(IllegalArgumentException::class.java)
    }
}
```

Keep utilities app-agnostic: no feature names, no datasource access, no
application configuration.

## 6. Exception library

`lib/exception/src/main/kotlin/com/shopease/exception/ApiException.kt`

```kotlin
package com.shopease.exception

import org.springframework.http.HttpStatus

abstract class ApiException(
    val status: HttpStatus,
    override val message: String,
) : RuntimeException(message)
```

`lib/exception/src/main/kotlin/com/shopease/exception/NotFoundException.kt`

```kotlin
package com.shopease.exception

import org.springframework.http.HttpStatus

class NotFoundException(message: String) :
    ApiException(HttpStatus.NOT_FOUND, message)
```

`lib/exception/src/main/kotlin/com/shopease/exception/ApiExceptionHandler.kt`

```kotlin
package com.shopease.exception

import org.springframework.http.ProblemDetail
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice

@RestControllerAdvice
class ApiExceptionHandler {
    @ExceptionHandler(ApiException::class)
    fun handleApiException(exception: ApiException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(exception.status, exception.message)
}
```

`lib/exception/src/main/kotlin/com/shopease/exception/ApiExceptionAutoConfiguration.kt`

```kotlin
package com.shopease.exception

import org.springframework.boot.autoconfigure.AutoConfiguration
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean
import org.springframework.context.annotation.Bean

@AutoConfiguration
class ApiExceptionAutoConfiguration {
    @Bean
    @ConditionalOnMissingBean
    fun apiExceptionHandler(): ApiExceptionHandler = ApiExceptionHandler()
}
```

`lib/exception/src/main/resources/META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports`

```text
com.shopease.exception.ApiExceptionAutoConfiguration
```

- The app's `@SpringBootApplication` lives in `com.shopease.<app>` and
  will not scan `com.shopease.exception`. Auto-configuration is what makes
  the handler a bean.
- If the repository avoids auto-configuration, annotate the app with
  `@Import(ApiExceptionHandler::class)` instead and drop the
  auto-configuration class and imports file.

Tests:

`lib/exception/src/test/kotlin/com/shopease/exception/ApiExceptionHandlerTest.kt`

```kotlin
package com.shopease.exception

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test

class ApiExceptionHandlerTest {
    private val handler = ApiExceptionHandler()

    @Test
    fun `maps a not-found exception to 404`() {
        val detail = handler.handleApiException(NotFoundException("Order 1 not found"))

        assertThat(detail.status).isEqualTo(404)
        assertThat(detail.detail).isEqualTo("Order 1 not found")
    }
}
```

Auto-configuration test:

```kotlin
package com.shopease.exception

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.boot.autoconfigure.AutoConfigurations
import org.springframework.boot.test.context.runner.ApplicationContextRunner

class ApiExceptionAutoConfigurationTest {
    private val contextRunner = ApplicationContextRunner()
        .withConfiguration(AutoConfigurations.of(ApiExceptionAutoConfiguration::class.java))

    @Test
    fun `registers the handler bean`() {
        contextRunner.run { context ->
            assertThat(context).hasSingleBean(ApiExceptionHandler::class.java)
        }
    }
}
```

## 7. Mapper library

`lib/mapper/src/main/kotlin/com/shopease/mapper/Mapper.kt`

```kotlin
package com.shopease.mapper

fun interface Mapper<in S, out T> {
    fun map(source: S): T
}

fun <S, T> Iterable<S>.mapWith(mapper: Mapper<S, T>): List<T> =
    map(mapper::map)
```

- Keep feature-specific mappers in the feature packages of the app. The
  library holds only the shared contract and helpers.
- If the project already uses MapStruct, shared `@MapperConfig` types can
  live here; add `implementation(libs.mapstruct)` and
  `kapt(libs.mapstruct.processor)`. Do not introduce MapStruct just for
  the library.

Test:

```kotlin
package com.shopease.mapper

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test

class MapperTest {
    @Test
    fun `maps every element`() {
        val result = listOf(1, 2).mapWith { it * 2 }

        assertThat(result).containsExactly(2, 4)
    }
}
```

The lambda satisfies the `fun interface`, so no extra class is needed.

## 8. Wire the library into an application

```kotlin
dependencies {
    implementation(project(":lib:exception"))
    implementation(project(":lib:common"))
}
```

- Add only the libraries the app uses.
- Do not add a `project(...)` on another application.
- Runtime properties/configuration stay in the app; do not let a library
  read app-specific keys.

## 9. Dependency checklist

| Library contains        | Needs |
| ----------------------- | ----- |
| Utilities/constants     | Kotlin JVM + `java-library`; test starter |
| Mapping helpers         | Kotlin JVM + `java-library`; test starter |
| Exception types/advice  | `api` `spring-web`; `compileOnly` `spring-boot-autoconfigure` + `testImplementation` for auto-config tests; test starter |
| Shared DTOs with Jackson | `api` `jackson-module-kotlin` |
| Shared DTOs with validation | `api` `jakarta.validation-api` |
| MapStruct mappers       | `implementation` MapStruct + `kapt` processor, only if already used |
| Persistence helpers     | `api`/`implementation` Spring Data/JPA modules, never a datasource or migrations |

## 10. Validation

```bash
./gradlew projects
./gradlew :lib:exception:compileKotlin
./gradlew :lib:exception:test
./gradlew :shop-service:compileKotlin
./gradlew :shop-service:test
```

The app context test is the proof that auto-configuration works without
widening component scanning.
