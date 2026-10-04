plugins {
    alias(libs.plugins.android.application) apply false
    // Not applied: AGP 9 compiles Kotlin itself. Declaring it pins the Kotlin
    // Gradle Plugin version AGP uses, keeping it in step with the Compose
    // compiler plugin.
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.ktlint) apply false
}
