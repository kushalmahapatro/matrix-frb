import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load keystore properties
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.matrix"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.matrix"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        getByName("profile") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

val buildConfigs = listOf(
    Pair("Debug", ""),
    Pair("Profile", "--release"),
    Pair("Release", "--release")
)

buildConfigs.forEach { (taskPostfix, profileMode) ->
    tasks.whenTaskAdded(Action {
        if (name == "javaPreCompile$taskPostfix") {
            dependsOn("cargoBuild$taskPostfix")
        }
    })
    tasks.register("cargoBuild$taskPostfix", Exec::class) {
        // Until https://github.com/bbqsrc/cargo-ndk/pull/13 is merged,
        // this workaround is necessary.

        val ndkCommand = """cargo ndk \
            -t armeabi-v7a -t arm64-v8a -t x86_64 -t x86 \
            -o ../android/app/src/main/jniLibs build $profileMode"""

        workingDir("../../rust")
        // val ndkPath = System.getenv("ANDROID_NDK_HOME") ?: System.getenv("ANDROID_NDK") ?: ""
        // environment("ANDROID_NDK_HOME", ndkPath)
        // environment("ANDROID_NDK", ndkPath)
        if (System.getProperty("os.name").lowercase().contains("windows")) {
            commandLine("cmd", "/C", ndkCommand)
        } else {
            commandLine("sh", "-c", ndkCommand)
        }
    }
}