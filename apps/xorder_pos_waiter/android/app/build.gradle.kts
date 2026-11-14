plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.xorder.xorder_pos_waiter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.xorder.xorder_pos_waiter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // AGP 8+ turns resValue off by default; the flavors' app_name needs it.
    buildFeatures {
        resValues = true
    }

    // Two apps from one codebase, the mode fixed per build (owner decision,
    // 2026-11-09). Each flavor has its own id and name so both can sit on one
    // phone; the Dart side is fixed by the matching entry point:
    //   flutter build apk --flavor cloud   -t lib/main_cloud.dart
    //   flutter build apk --flavor offline -t lib/main_offline.dart
    flavorDimensions += "mode"
    productFlavors {
        create("cloud") {
            dimension = "mode"
            applicationIdSuffix = ".cloud"
            resValue("string", "app_name", "XOrder Waiter Cloud")
        }
        create("offline") {
            dimension = "mode"
            applicationIdSuffix = ".offline"
            resValue("string", "app_name", "XOrder Waiter Offline")
        }
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
