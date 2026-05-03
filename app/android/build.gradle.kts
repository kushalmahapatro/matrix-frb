allprojects {
    repositories {
        google()
        mavenCentral()
        // rustls-platform-verifier Android AAR from Cargo cache (TLS cert verification on Android)
        maven {
            url = findRustlsPlatformVerifierMaven()
            content { includeGroup("rustls") }
        }
    }
}

fun findRustlsPlatformVerifierMaven(): java.net.URI {
    val manifestPath = rootProject.file("../../sdk/rust/Cargo.toml").absolutePath
    val out = java.io.ByteArrayOutputStream()
    rootProject.exec {
        workingDir = rootProject.file("../..")
        commandLine("cargo", "metadata", "--format-version", "1", "--filter-platform", "aarch64-linux-android", "--manifest-path", manifestPath)
        standardOutput = out
    }
    val json = out.toString()
    val label = "\"manifest_path\":\""
    var searchStart = 0
    while (true) {
        val start = json.indexOf(label, searchStart)
        if (start < 0) break
        val pathStart = start + label.length
        val pathEnd = json.indexOf("\"", pathStart)
        val pkgManifest = json.substring(pathStart, pathEnd).replace("\\\\", "/")
        if (pkgManifest.contains("rustls-platform-verifier-android")) {
            val mavenDir = java.io.File(pkgManifest).parentFile.resolve("maven")
            require(mavenDir.isDirectory) { "rustls-platform-verifier maven dir missing: $mavenDir" }
            return mavenDir.toURI()
        }
        searchStart = pathEnd + 1
    }
    throw IllegalStateException("rustls-platform-verifier-android not in cargo metadata (run from repo root?)")
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
