import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "io.github.benediktburger.cycleapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            // A relative `storeFile` value resolves against the `:app` module
            // directory (`android/app/`); prefer absolute paths in key.properties
            // (as templated in docs/release.md).
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // MainActivity keys its FLAG_SECURE gate on BuildConfig.DEBUG; AGP
        // no longer generates the BuildConfig class by default.
        buildConfig = true
    }

    defaultConfig {
        applicationId = "io.github.benediktburger.cycleapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml as the base; split APKs get
        // N*10 + abiCode via the abiCodes override below.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else if (providers.gradleProperty("allowDebugSigning").isPresent) {
                // The release workflow's CI run has no keystore: it opts into
                // debug-keyed artifacts explicitly, and the local apksigner
                // step replaces those signature blocks before anything ships
                // (docs/release.md Phase C + per-release checklist).
                signingConfig = signingConfigs.getByName("debug")
            }
            // Without key.properties and without the explicit opt-in the
            // signing config stays unset: the task-graph gate below fails
            // the build, so no release artifact leaves this module
            // debug-signed (or unsigned) by accident.
        }
    }

    dependenciesInfo {
        // Disables dependency metadata when building APKs.
        includeInApk = false
        // Disables dependency metadata when building Android App Bundles.
        includeInBundle = false
    }
}

// Split APKs get versionCode N*10 + abiCode (1 = armeabi-v7a, 2 = arm64-v8a,
// 3 = x86_64), where N is the pubspec versionCode. The universal APK has no
// ABI filter and keeps exactly the pubspec versionCode.
val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)
android.applicationVariants.configureEach {
    val variant = this
    variant.outputs.forEach { output ->
        val abiVersionCode = abiCodes[output.filters.find { it.filterType == "ABI" }?.identifier]
        if (abiVersionCode != null) {
            (output as ApkVariantOutputImpl).versionCodeOverride = variant.versionCode * 10 + abiVersionCode
        }
    }
}

// Release signing gate (docs/release.md Phase C): a release build without
// the provisioned keystore must fail at the task graph instead of silently
// producing a debug-signed (or unsigned) artifact that is easy to ship by
// mistake. The `-PallowDebugSigning` opt-in is for the release workflow's
// CI run, whose artifacts are re-signed locally with apksigner.
gradle.taskGraph.whenReady {
    if (allTasks.none { it.name.contains("Release") }) return@whenReady

    if (keystorePropertiesFile.exists()) {
        val storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
        if (storeFile == null || !storeFile.exists()) {
            throw GradleException(
                "key.properties must name an existing release keystore via " +
                    "storeFile (current value: " +
                    "${keystoreProperties.getProperty("storeFile")}); see " +
                    "docs/release.md Phase C for the provisioning.",
            )
        }
    } else if (!providers.gradleProperty("allowDebugSigning").isPresent) {
        throw GradleException(
            "Release builds fail without the signing provisioning: point " +
                "android/key.properties at the release keystore (docs/release.md " +
                "Phase C). The release workflow's CI build passes " +
                "-PallowDebugSigning instead (its artifacts are re-signed " +
                "locally with apksigner).",
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
