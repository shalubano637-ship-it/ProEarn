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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.proearn"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
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
            storePassword = properties.getProperty("storePassword")?.takeIf { it.isNotBlank() }
                ?: throw GradleException("key.properties is missing storePassword")
            keyAlias = properties.getProperty("keyAlias")?.takeIf { it.isNotBlank() }
                ?: throw GradleException("key.properties is missing keyAlias")
            keyPassword = properties.getProperty("keyPassword")?.takeIf { it.isNotBlank() }
                ?: throw GradleException("key.properties is missing keyPassword")
            storeFile = rootProject.file(storePath)
            if (storeFile?.isFile != true) {
                throw GradleException("Release keystore not found at: $storePath")
            }
        }
    }

    buildTypes {
        release {
            // Never produce a debug-signed artifact under the release build type.
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
