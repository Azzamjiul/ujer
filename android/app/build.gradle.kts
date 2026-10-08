import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

val signingProperties = Properties().apply {
    val file = rootProject.file("keystore.properties")
    if (file.isFile) {
        file.inputStream().use(::load)
    }
}

if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
    val required = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    check(required.all(signingProperties::containsKey)) {
        "Release signing is not configured. Create android/keystore.properties from " +
            "android/keystore.properties.example."
    }
    check(rootProject.file(signingProperties.getProperty("storeFile")).isFile) {
        "Release signing storeFile does not exist: ${signingProperties.getProperty("storeFile")}"
    }
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "cc.alat.ujer"
    compileSdk = 36

    defaultConfig {
        applicationId = "cc.alat.ujer"
        minSdk = 29
        targetSdk = 36
        versionCode = 1
        versionName = "0.0.1"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures { compose = true }
    signingConfigs {
        create("release") {
            storeFile = signingProperties.getProperty("storeFile")?.let(::file)
            storePassword = signingProperties.getProperty("storePassword")
            keyAlias = signingProperties.getProperty("keyAlias")
            keyPassword = signingProperties.getProperty("keyPassword")
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            signingConfig = signingConfigs.getByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin { compilerOptions { jvmTarget.set(JvmTarget.JVM_17) } }

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2026.06.00")
    implementation(composeBom)
    implementation("androidx.activity:activity-compose:1.12.4")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.9.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20250517")
}
