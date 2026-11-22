# Spring Boot Kotlin application templates

One application = one Gradle module, one `main` class, one config file.
Features are packages inside the application. Adapt names and remove
anything the app does not need.

The examples use an application named `shop-service` with base package
`com.shopease.shop` and an `orders` feature.

## 1. Bootstrap the root build

Target state when the repository has no Kotlin application yet. Keep the
existing toolchain value and root conventions; the example uses 21. There
is no `java-library` here: applications are not libraries.

```kotlin
import org.jetbrains.kotlin.gradle.dsl.KotlinJvmProjectExtension

plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.spring) apply false
    alias(libs.plugins.kotlin.jpa) apply false
    alias(libs.plugins.spring.boot) apply false
}

subprojects {
    apply(plugin = "org.jetbrains.kotlin.jvm")

    group = rootProject.group
    version = rootProject.version

    repositories {
        mavenCentral()
    }

    extensions.configure<KotlinJvmProjectExtension> {
        jvmToolchain(21)
        compilerOptions {
            freeCompilerArgs.addAll(
                "-Xjsr305=strict",
                "-Xannotation-default-target=param-property",
            )
        }
    }

    tasks.withType<Test>().configureEach {
        useJUnitPlatform()
    }
}
```

- `jvmToolchain` sets the Java and Kotlin toolchains together; do not add
  a separate `jvmTarget` that can drift.
- The Spring Boot plugin stays `apply false` at the root. Every
  application applies it itself.
- If the root already applies plugins per application instead of in
  `subprojects`, keep that model and omit the plugin lines from the app
  build file.

## 2. Catalog entries

Add only what is missing. The `kotlin` value is the BOM's managed Kotlin
version, reported by
`scripts/verify-dependency.sh org.jetbrains.kotlin:kotlin-stdlib`.

```toml
[versions]
kotlin = "<managed_version from the Spring Boot BOM>"
spring-boot = "<existing value>"

[libraries]
kotlin-reflect = { module = "org.jetbrains.kotlin:kotlin-reflect" }
jackson-module-kotlin = { module = "com.fasterxml.jackson.module:jackson-module-kotlin" }
spring-boot-devtools = { module = "org.springframework.boot:spring-boot-devtools" }
spring-boot-starter-webmvc = { module = "org.springframework.boot:spring-boot-starter-webmvc" }
spring-boot-starter-webmvc-test = { module = "org.springframework.boot:spring-boot-starter-webmvc-test" }
spring-boot-starter-data-jpa-test = { module = "org.springframework.boot:spring-boot-starter-data-jpa-test" }
# existing starters stay versionless

[plugins]
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
kotlin-spring = { id = "org.jetbrains.kotlin.plugin.spring", version.ref = "kotlin" }
kotlin-jpa = { id = "org.jetbrains.kotlin.plugin.jpa", version.ref = "kotlin" }
```

Every starter, `kotlin-reflect`, `jackson-module-kotlin`, and DevTools is
BOM-managed, so none carries a version. Do not add a `kotlin-stdlib`
entry. On Spring Boot 3.x, substitute `spring-boot-starter-web` and the
legacy test-slice packages.

## 3. Settings

```kotlin
rootProject.name = "shopease"

include(":shop-service")
# include(":another-service")  // each application is a sibling
```

Each application gets one include. Never add includes for feature
packages.

## 4. Application build file

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

- Drop `kotlin-jpa`, `data-jpa`, and `data-jpa-test` when the app has no
  persistence.
- Drop the web starter and web test starter for a non-web app.
- No `java-library`, no `api`, no `project(...)` dependency on another
  application.

## 5. Entry point, configuration, context test

`shop-service/src/main/kotlin/com/shopease/shop/ShopServiceApplication.kt`

```kotlin
package com.shopease.shop

import org.springframework.boot.autoconfigure.SpringBootApplication
import org.springframework.boot.runApplication

@SpringBootApplication
class ShopServiceApplication

fun main(args: Array<String>) {
    runApplication<ShopServiceApplication>(*args)
}
```

`shop-service/src/main/resources/application.yml`

```yaml
spring:
  application:
    name: shop-service

server:
  port: 8081
```

Pick a port that no sibling application uses. Add datasource/JPA/Flyway
configuration only when the app actually uses them; do not invent
credentials.

`shop-service/src/test/kotlin/com/shopease/shop/ShopServiceApplicationTests.kt`

```kotlin
package com.shopease.shop

import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.SpringBootTest

@SpringBootTest
class ShopServiceApplicationTests {
    @Test
    fun contextLoads() {
    }
}
```

## 6. Package layout

```text
shop-service/
├── build.gradle.kts
└── src/
    ├── main/kotlin/com/shopease/shop/
    │   ├── ShopServiceApplication.kt
    │   ├── config/
    │   └── orders/                    <- feature package
    │       ├── controller/
    │       │   └── OrderController.kt
    │       ├── service/
    │       │   └── OrderService.kt
    │       ├── repository/
    │       │   └── OrderRepository.kt
    │       ├── entity/
    │       │   └── OrderEntity.kt
    │       ├── dto/
    │       │   ├── CreateOrderRequest.kt
    │       │   └── OrderResponse.kt
    │       ├── mapper/
    │       │   └── OrderMapper.kt
    │       └── exception/
    │           ├── OrderNotFoundException.kt
    │           └── OrderExceptionHandler.kt
    ├── main/resources/
    │   ├── application.yml
    │   └── db/migration/              <- if this app owns Flyway migrations
    └── test/kotlin/com/shopease/shop/
        ├── ShopServiceApplicationTests.kt
        └── orders/
            ├── service/OrderServiceTest.kt
            └── controller/OrderControllerTest.kt
```

Add only the layers a feature uses. `config/` holds app-specific
infrastructure. Mappers, exception types/advice, DTOs, and utilities that
more than one app needs belong in a `:lib:<name>` module created with the
`add-kotlin-library` skill, consumed as
`implementation(project(":lib:<name>"))`.

## 7. Controller

`.../orders/controller/OrderController.kt`

```kotlin
package com.shopease.shop.orders.controller

import com.shopease.shop.orders.dto.CreateOrderRequest
import com.shopease.shop.orders.dto.OrderResponse
import com.shopease.shop.orders.mapper.toResponse
import com.shopease.shop.orders.service.OrderService
import jakarta.validation.Valid
import org.springframework.http.HttpStatus
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.ResponseStatus
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/v1/orders")
class OrderController(
    private val service: OrderService,
) {
    @GetMapping
    fun findAll(): List<OrderResponse> =
        service.findAll().map { it.toResponse() }

    @GetMapping("/{id}")
    fun findById(@PathVariable id: Long): OrderResponse =
        service.findById(id).toResponse()

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun create(@Valid @RequestBody request: CreateOrderRequest): OrderResponse =
        service.create(request).toResponse()
}
```

## 8. Service

`.../orders/service/OrderService.kt`

```kotlin
package com.shopease.shop.orders.service

import com.shopease.shop.orders.dto.CreateOrderRequest
import com.shopease.shop.orders.entity.OrderEntity
import com.shopease.shop.orders.exception.OrderNotFoundException
import com.shopease.shop.orders.repository.OrderRepository
import org.springframework.data.repository.findByIdOrNull
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
@Transactional(readOnly = true)
class OrderService(
    private val repository: OrderRepository,
) {
    fun findAll(): List<OrderEntity> = repository.findAll()

    fun findById(id: Long): OrderEntity = repository.findByIdOrNull(id)
        ?: throw OrderNotFoundException(id)

    @Transactional
    fun create(request: CreateOrderRequest): OrderEntity =
        repository.save(OrderEntity(customer = request.customer))
}
```

## 9. Repository and entity

`.../orders/repository/OrderRepository.kt`

```kotlin
package com.shopease.shop.orders.repository

import com.shopease.shop.orders.entity.OrderEntity
import org.springframework.data.jpa.repository.JpaRepository

interface OrderRepository : JpaRepository<OrderEntity, Long>
```

`.../orders/entity/OrderEntity.kt`

```kotlin
package com.shopease.shop.orders.entity

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.GeneratedValue
import jakarta.persistence.GenerationType
import jakarta.persistence.Id
import jakarta.persistence.Table

@Entity
@Table(name = "orders")
class OrderEntity(
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    var id: Long? = null,

    @Column(nullable = false, length = 120)
    var customer: String = "",
)
```

- Not a `data class`: entity identity is the database id.
- The `kotlin-jpa` plugin supplies the no-arg constructor.
- Own migrations in this app; never rely on `ddl-auto` for schema.

## 10. DTOs and mapper

`.../orders/dto/CreateOrderRequest.kt`

```kotlin
package com.shopease.shop.orders.dto

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size

data class CreateOrderRequest(
    @field:NotBlank
    @field:Size(max = 120)
    val customer: String,
)
```

`.../orders/dto/OrderResponse.kt`

```kotlin
package com.shopease.shop.orders.dto

data class OrderResponse(
    val id: Long,
    val customer: String,
)
```

`.../orders/mapper/OrderMapper.kt`

```kotlin
package com.shopease.shop.orders.mapper

import com.shopease.shop.orders.dto.OrderResponse
import com.shopease.shop.orders.entity.OrderEntity

fun OrderEntity.toResponse(): OrderResponse =
    OrderResponse(
        id = requireNotNull(id) { "Order must be persisted before mapping" },
        customer = customer,
    )
```

Keep mapping in one file (`toResponse`, `toEntity`) so the API/entity
boundary is auditable.

## 11. Exception and advice

`.../orders/exception/OrderNotFoundException.kt`

```kotlin
package com.shopease.shop.orders.exception

class OrderNotFoundException(id: Long) :
    RuntimeException("Order $id not found")
```

`.../orders/exception/OrderExceptionHandler.kt`

```kotlin
package com.shopease.shop.orders.exception

import org.springframework.http.HttpStatus
import org.springframework.http.ProblemDetail
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice

@RestControllerAdvice
class OrderExceptionHandler {
    @ExceptionHandler(OrderNotFoundException::class)
    fun handleNotFound(exception: OrderNotFoundException): ProblemDetail =
        ProblemDetail.forStatusAndDetail(
            HttpStatus.NOT_FOUND,
            exception.message ?: "Order not found",
        )
}
```

If the application already has an app-wide advice in `config/` (or a
`:lib:<name>` shared exception library), add the handler there and delete
the feature-local advice. Do not register two advices for the same
exception type.

## 12. Feature tests

### Service unit test

`shop-service/src/test/kotlin/com/shopease/shop/orders/service/OrderServiceTest.kt`

```kotlin
package com.shopease.shop.orders.service

import com.shopease.shop.orders.dto.CreateOrderRequest
import com.shopease.shop.orders.entity.OrderEntity
import com.shopease.shop.orders.exception.OrderNotFoundException
import com.shopease.shop.orders.repository.OrderRepository
import java.util.Optional
import org.assertj.core.api.Assertions.assertThat
import org.assertj.core.api.Assertions.assertThatThrownBy
import org.junit.jupiter.api.Test
import org.mockito.ArgumentMatchers.any
import org.mockito.Mockito.`when`
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify

class OrderServiceTest {
    private val repository: OrderRepository = mock(OrderRepository::class.java)
    private val service = OrderService(repository)

    @Test
    fun `create saves and returns the entity`() {
        `when`(repository.save(any(OrderEntity::class.java)))
            .thenAnswer { it.arguments[0] as OrderEntity }

        val result = service.create(CreateOrderRequest(customer = "Ada"))

        assertThat(result.customer).isEqualTo("Ada")
        verify(repository).save(any(OrderEntity::class.java))
    }

    @Test
    fun `findById throws when the entity does not exist`() {
        `when`(repository.findById(99L)).thenReturn(Optional.empty())

        assertThatThrownBy { service.findById(99L) }
            .isInstanceOf(OrderNotFoundException::class.java)
    }
}
```

Use the project's existing mocking library instead if it is not Mockito.

### Controller slice test

`shop-service/src/test/kotlin/com/shopease/shop/orders/controller/OrderControllerTest.kt`

```kotlin
package com.shopease.shop.orders.controller

import com.shopease.shop.orders.dto.CreateOrderRequest
import com.shopease.shop.orders.entity.OrderEntity
import com.shopease.shop.orders.service.OrderService
import org.junit.jupiter.api.Test
import org.mockito.Mockito.`when`
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest
import org.springframework.http.MediaType
import org.springframework.test.context.bean.override.mockito.MockitoBean
import org.springframework.test.web.servlet.MockMvc
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status

@WebMvcTest(OrderController::class)
class OrderControllerTest(
    @Autowired private val mockMvc: MockMvc,
) {
    @MockitoBean
    private lateinit var service: OrderService

    @Test
    fun `POST creates an order`() {
        `when`(service.create(CreateOrderRequest(customer = "Ada")))
            .thenReturn(OrderEntity(id = 1L, customer = "Ada"))

        mockMvc.perform(
            post("/api/v1/orders")
                .contentType(MediaType.APPLICATION_JSON)
                .content("""{"customer":"Ada"}"""),
        )
            .andExpect(status().isCreated())
            .andExpect(jsonPath("$.customer").value("Ada"))
    }
}
```

Because the test lives under the application's base package, the app's
own `@SpringBootApplication` class provides the test configuration. No
test-only application class is needed.

### Repository test

Generate only when the project already has an embedded database or
Testcontainers, and add
`testImplementation(libs.spring.boot.starter.data.jpa.test)`:

```kotlin
package com.shopease.shop.orders.repository

import com.shopease.shop.orders.entity.OrderEntity
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest

@DataJpaTest
class OrderRepositoryTest(
    @Autowired private val repository: OrderRepository,
) {
    @Test
    fun `saves and reads an entity`() {
        val saved = repository.save(OrderEntity(customer = "Ada"))

        assertThat(repository.findById(saved.id!!)).isPresent()
    }
}
```

Otherwise report "repository test needs a test database" as follow-up.

## 13. Configuration, ports, migrations

- Every app defines `spring.application.name` and a unique `server.port`.
- If apps run together, also give each its own database/schema.
- Datasource credentials come from the project's environment convention;
  never hard-code secrets.
- Flyway/Liquibase migrations belong to the app that owns the schema.
  Keep versions unique within that app.
- Do not add actuator, security, Docker, or profiles unless the
  requirements ask for them.

## 14. Dependency checklist

| App contains            | Needs |
| ----------------------- | ----- |
| REST controllers        | `spring-boot-starter-webmvc`, `spring-boot-starter-validation` |
| JSON DTOs               | `jackson-module-kotlin` |
| Spring proxies          | `kotlin-spring` plugin, `kotlin-reflect` |
| JPA entity/repository   | `spring-boot-starter-data-jpa`, `kotlin-jpa` plugin, driver at `runtimeOnly` |
| Configuration properties| `kotlin-reflect`, constructor binding enabled |
| Processor (MapStruct, Dagger) | `kapt`/`ksp` configuration and plugin |
| Unit/service tests      | `spring-boot-starter-test` (included by slice starters) |
| Controller slice tests  | `spring-boot-starter-webmvc-test` |
| Repository slice tests  | `spring-boot-starter-data-jpa-test` |
| Dev-time tooling        | `spring-boot-devtools` via `developmentOnly` |

On Spring Boot 3.x, use `spring-boot-starter-web` and the legacy
`spring-boot-starter-test` slice packages instead of the Boot 4 names.
Do not add a dependency unless the generated code needs it.
