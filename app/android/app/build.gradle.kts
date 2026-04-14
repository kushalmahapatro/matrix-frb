import java.io.File
import java.io.FileInputStream
import java.net.URI
import java.util.Properties
import java.util.zip.ZipInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load keystore properties (optional; debug uses the default debug keystore).
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val releaseStoreFile = keystoreProperties.getProperty("storeFile")?.let { rootProject.file(it) }

android {
    namespace = "dev.inve.matrixchat"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
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


    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = releaseStoreFile
            storePassword = keystoreProperties.getProperty("storePassword")
        }

    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
        // Use getByName: bare `profile { }` clashes with Kotlin Gradle DSL (KotlinSourceSet.profile).
        getByName("profile") {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

// Rust LiveKit / libwebrtc JNI needs Java classes from libwebrtc.jar (e.g. livekit.org.jni_zero.JniInit).
// Always depend on app/libs/libwebrtc.jar so AGP merges it into the app DEX reliably (paths under
// build/ or outside this module have been observed to omit JNI helper classes at runtime).
// preBuild materializes that file from: Cargo webrtc-sys output, an existing libs jar, a legacy
// bootstrap copy under build/, or a download matching webrtc-sys-build WEBRTC_TAG.
val repoRoot: File =
    rootProject.projectDir.resolve("..").resolve("..").normalize()
val libwebrtcDest: File = file("libs/libwebrtc.jar")

fun libwebrtcFromCargoPaths(): List<File> {
    val triples = listOf(
        "aarch64-linux-android",
        "x86_64-linux-android",
        "armv7-linux-androideabi",
        "i686-linux-android",
    )
    val profiles = listOf("release", "debug")
    return triples.flatMap { t ->
        profiles.map { p ->
            repoRoot.resolve("sdk/rust/patches/target/$t/$p/libwebrtc.jar")
        }
    }
}

val libwebrtcBootstrapDir: File =
    layout.buildDirectory.dir("libwebrtc").get().asFile
val libwebrtcBootstrappedLegacy: File = File(libwebrtcBootstrapDir, "libwebrtc.jar")

// Must match `webrtc-sys-build` WEBRTC_TAG + Android arm64 release prebuilt name.
val libwebrtcReleaseTag = "webrtc-7af9351"
val libwebrtcZipName = "webrtc-android-arm64-release.zip"
val libwebrtcZipUrl =
    "https://github.com/livekit/rust-sdks/releases/download/$libwebrtcReleaseTag/$libwebrtcZipName"

tasks.register("bootstrapLibwebrtcJar") {
    description =
        "Ensures libs/libwebrtc.jar exists (copy from Cargo, legacy bootstrap, or download)."
    outputs.file(libwebrtcDest)

    onlyIf {
        !libwebrtcDest.isFile
    }

    doLast {
        if (libwebrtcDest.isFile) {
            return@doLast
        }
        libwebrtcDest.parentFile?.mkdirs()

        val fromCargo = libwebrtcFromCargoPaths().firstOrNull { it.isFile }
        if (fromCargo != null) {
            fromCargo.copyTo(libwebrtcDest, overwrite = true)
            return@doLast
        }
        if (libwebrtcBootstrappedLegacy.isFile) {
            libwebrtcBootstrappedLegacy.copyTo(libwebrtcDest, overwrite = true)
            return@doLast
        }

        libwebrtcBootstrapDir.mkdirs()
        val tmpZip = File.createTempFile("webrtc-prebuilt-", ".zip", libwebrtcBootstrapDir)
        try {
            URI.create(libwebrtcZipUrl).toURL().openStream().use { input ->
                tmpZip.outputStream().use { output -> input.copyTo(output) }
            }
            var found = false
            tmpZip.inputStream().use { fis ->
                ZipInputStream(fis).use { zis ->
                    var entry = zis.nextEntry
                    while (entry != null) {
                        if (!entry.isDirectory && entry.name.endsWith("libwebrtc.jar")) {
                            libwebrtcDest.outputStream().use { out -> zis.copyTo(out) }
                            found = true
                            break
                        }
                        entry = zis.nextEntry
                    }
                }
            }
            if (!found || !libwebrtcDest.isFile) {
                throw org.gradle.api.GradleException(
                    "Could not extract libwebrtc.jar from $libwebrtcZipUrl (layout changed?). " +
                        "Place the jar at app/android/app/libs/libwebrtc.jar manually.",
                )
            }
        } finally {
            tmpZip.delete()
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // TLS certificate verification on Android (required by rustls in Matrix SDK).
    // @aar: crate ships an AAR; without it Gradle may look for a .jar and fail resolution.
    implementation("rustls:rustls-platform-verifier:0.1.1@aar")
    implementation(files(libwebrtcDest))
}

tasks.named("preBuild").configure {
    dependsOn("bootstrapLibwebrtcJar")
}

flutter {
    source = "../.."
}
