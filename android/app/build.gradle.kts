import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

android {
    namespace = "com.prosn.app"
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
        applicationId = "com.prosn.app"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keyPropertiesFile = rootProject.file("key.properties")
            if (!keyPropertiesFile.isFile) {
                throw GradleException("Persistent signing key is mandatory. android/key.properties is missing.")
            }
            val properties = Properties().apply { load(FileInputStream(keyPropertiesFile)) }
            val storePath = properties.getProperty("storeFile")?.takeIf { it.isNotBlank() }
                ?: throw GradleException("key.properties is missing storeFile")
            storeFile = rootProject.file(storePath)
            storePassword = properties.getProperty("storePassword")
                ?: throw GradleException("key.properties is missing storePassword")
            keyAlias = properties.getProperty("keyAlias")
                ?: throw GradleException("key.properties is missing keyAlias")
            keyPassword = properties.getProperty("keyPassword")
                ?: throw GradleException("key.properties is missing keyPassword")
            if (!storeFile!!.isFile) {
                throw GradleException("Persistent signing keystore not found: $storePath")
            }
        }
    }

    buildTypes {
        debug {
            // No temporary/default Android debug keystore fallback is permitted.
            signingConfig = signingConfigs.getByName("release")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
}

flutter {
    source = "../.."
}

// Every Android build requires the persistent signing key; debug builds cannot fall back to a runner-generated key.
gradle.taskGraph.whenReady {
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
