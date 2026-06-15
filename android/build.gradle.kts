plugins {
    id("com.google.gms.google-services") version "4.4.2" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // geolocator_android pins androidx.core:core to 1.16.0, an artifact
    // version that Flutter's download.flutter.io Maven mirror currently
    // 403s on (it isn't mirrored yet). Every other plugin in the graph
    // already resolves to 1.18.0 — force that version everywhere so
    // Gradle never attempts to fetch the missing 1.16.0 POM at all.
    configurations.all {
        resolutionStrategy {
            force("androidx.core:core:1.18.0")
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}