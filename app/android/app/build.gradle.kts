plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties
// val keystorePropertiesFile = rootProject.file("keystore.properties")
// val keystoreProperties = Properties()
// if (keystorePropertiesFile.exists()) {
//     keystoreProperties.load(FileInputStream(keystorePropertiesFile))
// }

android {
    namespace = "dev.inve.matrixchat"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.inve.matrixchat"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    //  signingConfigs {
    //     create("release") {
    //         keyAlias = keystoreProperties["keyAlias"] as String?
    //         keyPassword = keystoreProperties["keyPassword"] as String?
    //         storeFile = keystoreProperties["storeFile"]?.let { file(it) }
    //         storePassword = keystoreProperties["storePassword"] as String?
    //     }
    // }

    // buildTypes {
    //     release {
    //         isMinifyEnabled = false
    //         isShrinkResources = false
    //     }
    //     profile {
    //         isMinifyEnabled = false
    //         isShrinkResources = false
    //     }
    //     release {
    //         signingConfig = signingConfigs.getByName("release")
    //         proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
    //         isMinifyEnabled = false
    //         isShrinkResources = false
    //     }
    // }
}

dependencies {
    // TLS certificate verification on Android (required by rustls in Matrix SDK).
    // @aar: crate ships an AAR; without it Gradle may look for a .jar and fail resolution.
    implementation("rustls:rustls-platform-verifier:0.1.1@aar")
}

flutter {
    source = "../.."
}
