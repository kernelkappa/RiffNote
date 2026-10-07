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

// Some plugins pin their own Java target but don't pin a matching Kotlin
// JVM target, so Kotlin floats to whatever JDK Gradle runs on instead — a
// mismatch Gradle refuses to build. AGP's compileOptions is a lazy
// Property that can't be read back safely at configuration time ("not yet
// finalized"), and afterEvaluate is unsafe here too (:app's evaluation is
// forced to finish early by `evaluationDependsOn(":app")` above, so
// calling it elsewhere risks "already evaluated"). So rather than
// introspecting each module, just pin the known offenders by name — the
// Gradle error always names the task/module, so extend this map if
// another plugin hits the same mismatch.
val kotlinJvmTargetOverrides = mapOf(
    "tflite_flutter" to org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11,
    "audioplayers_android" to org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17,
)
subprojects {
    kotlinJvmTargetOverrides[project.name]?.let { target ->
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(target)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
