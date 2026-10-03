plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Unsigned release builds are useful to F-Droid. Never fall back to debug signing.
val signingNames = listOf("WANDERLUST_RELEASE_KEYSTORE", "WANDERLUST_RELEASE_STORE_PASSWORD",
    "WANDERLUST_RELEASE_KEY_ALIAS", "WANDERLUST_RELEASE_KEY_PASSWORD")
val configuredSecrets = signingNames.count { !System.getenv(it).isNullOrBlank() }
require(configuredSecrets == 0 || configuredSecrets == signingNames.size) {
    "Set all four WANDERLUST_RELEASE signing variables, or none for unsigned artifacts"
}
val releaseKey = System.getenv("WANDERLUST_RELEASE_KEYSTORE")?.takeIf { it.isNotBlank() }
fun signingSecret(name: String): String = requireNotNull(System.getenv(name)) {
    "Missing release signing environment variable: $name"
}

android {
    namespace = "com.simiono.wanderlust"
    compileSdk = 36
    ndkVersion = "28.2.13676358"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    defaultConfig {
        applicationId = "com.simiono.wanderlust"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        if (releaseKey != null) {
            create("production") {
                storeFile = file(releaseKey)
                storePassword = signingSecret("WANDERLUST_RELEASE_STORE_PASSWORD")
                keyAlias = signingSecret("WANDERLUST_RELEASE_KEY_ALIAS")
                keyPassword = signingSecret("WANDERLUST_RELEASE_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (releaseKey != null) signingConfigs.getByName("production") else null
        }
    }
}
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
flutter { source = "../.." }

// Check resolved Maven dependencies before shrinking can hide SDK class names.
val verifyFreeDependencies by tasks.registering {
    doLast {
        val forbidden = configurations.getByName("releaseRuntimeClasspath")
            .incoming.resolutionResult.allComponents.filter {
                val group = it.moduleVersion?.group.orEmpty()
                group.startsWith("com.google.android.gms") || group.startsWith("com.google.firebase")
            }
        check(forbidden.isEmpty()) { "Non-free runtime dependencies: $forbidden" }
    }
}
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(verifyFreeDependencies)
}
