plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.koshika.koshika"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "dev.koshika.koshika"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    flavorDimensions += "appType"
    productFlavors {
        create("lite") {
            dimension = "appType"
            applicationIdSuffix = ".lite"
            versionNameSuffix = "-lite"
        }
        create("full") {
            dimension = "appType"
        }
    }
}

// Strip llama.cpp native libs from the lite flavor APK.
// This runs after packaging to remove AI inference libraries,
// keeping the lite APK small (~15MB smaller).
androidComponents {
    onVariants(selector().withFlavor("appType" to "lite")) { variant ->
        variant.packaging.jniLibs.excludes.addAll(listOf(
            "**/libllama.so",
            "**/libggml*.so",
            "**/libmtmd.so",
            "**/libllamadart.so",
        ))
    }
}

flutter {
    source = "../.."
}
