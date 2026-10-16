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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Several Flutter plugins inherit Flutter's default compile SDK independently
// from the application module. flutter_plugin_android_lifecycle requires 36,
// so keep every Android library module on the same supported API level.
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.dsl.LibraryExtension> {
            compileSdk = 36
        }
    }
}

// Older plugins can assign their compile SDK later in their own build script.
// Apply the final value after each subproject has finished configuring.
gradle.afterProject {
    extensions.findByType<com.android.build.api.dsl.LibraryExtension>()
        ?.compileSdk = 36
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
