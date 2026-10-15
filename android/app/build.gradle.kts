plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.colorh.jianfei_dazi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.colorh.jianfei_dazi"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            // 瘦身优化：仅保留现代主流真机 64 位 ABI（arm64-v8a），剔除老旧 32 位与 x86_64，
            // 包体积从 ~42MB 骤降至 ~23MB（99% 现代 Android 手机均采用 64 位架构）。
            abiFilters += listOf("arm64-v8a")
        }
    }

    signingConfigs {
        create("release") {
            val keystoreFile = file("keystore/plan-maker.keystore")
            if (keystoreFile.exists()) {
                storeFile = keystoreFile
                storePassword = "Pmk2026@jianfei"
                keyAlias = "planmaker"
                keyPassword = "Pmk2026@jianfei"
                enableV1Signing = true
                enableV2Signing = true
            } else {
                initWith(getByName("debug"))
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

dependencies {
    // flutter_local_notifications 要求启用 core library desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
