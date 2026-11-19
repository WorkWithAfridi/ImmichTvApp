import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    // Built-in Kotlin is provided by AGP 9; the legacy Kotlin Gradle Plugin is not applied.
    // The Flutter Gradle Plugin must be applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Signing credentials are intentionally not committed. CI and fresh checkouts
// fall back to the default debug signing when they are unavailable.
val releaseStoreFile = keystoreProperties["storeFile"]?.let { file(it) }
val hasReleaseSigning =
    keystoreProperties["keyAlias"] != null &&
        keystoreProperties["keyPassword"] != null &&
        keystoreProperties["storePassword"] != null &&
        releaseStoreFile?.exists() == true

android {
    namespace = "com.workwithafridi.immichtv"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget = JvmTarget.JVM_17
        }
    }

    defaultConfig {
        // Stable application ID: changing it would create a separate app on
        // Android TV / Google TV devices and break saved-profile upgrades.
        applicationId = "com.workwithafridi.immichtv"
        // Keep the SDK floors driven by Flutter so TV and mobile builds stay
        // aligned with the plugin set.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = releaseStoreFile
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}
