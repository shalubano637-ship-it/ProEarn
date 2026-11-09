import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

android {
    namespace = "com.example.proearn"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(
                org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
            )
        }
    }

    defaultConfig {
        // Keep this package aligned with google-services.json and the Play listing. Do not change it after the first Play upload.
        applicationId = "com.example.proearn"
        minSdk = 26
        targetSdk = 36 // Google Play new-app and update requirement from 31 August 2026.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keyPropertiesFile = rootProject.file("key.properties")
            if (keyPropertiesFile.isFile) {
                val properties = Properties().apply {
                    load(FileInputStream(keyPropertiesFile))
                }
                val storePath = properties.getProperty("storeFile")
                if (!storePath.isNullOrBlank()) storeFile = rootProject.file(storePath)
                storePassword = properties.getProperty("storePassword")
                keyAlias = properties.getProperty("keyAlias")
                keyPassword = properties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Never fall back to the debug key. The task-graph check below
            // fails only release builds when the private upload keystore is absent.
            signingConfig = signingConfigs.getByName("release")

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}


// Gradle configures all build types even for a debug build. Validate signing only
// when a release task is actually requested so debug CI remains usable.
gradle.taskGraph.whenReady {
    val releaseRequested = allTasks.any { it.name.contains("Release", ignoreCase = true) }
    if (releaseRequested) {
        val keyPropertiesFile = rootProject.file("key.properties")
        if (!keyPropertiesFile.isFile) {
            throw GradleException(
                "Release signing is not configured. Create android/key.properties from key.properties.example and provide the private upload keystore."
            )
        }
        val properties = Properties().apply {
            load(FileInputStream(keyPropertiesFile))
        }
        val storePath = properties.getProperty("storeFile")?.takeIf { it.isNotBlank() }
            ?: throw GradleException("key.properties is missing storeFile")
        for (property in listOf("storePassword", "keyAlias", "keyPassword")) {
            if (properties.getProperty(property).isNullOrBlank()) {
                throw GradleException("key.properties is missing $property")
            }
        }
        if (!rootProject.file(storePath).isFile) {
            throw GradleException("Release keystore not found at: $storePath")
        }
    }
}
