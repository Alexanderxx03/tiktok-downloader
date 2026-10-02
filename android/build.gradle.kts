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

subprojects {
    val project = this
    if (project.name != "app") {
        if (project.state.executed) {
            if (project.hasProperty("android")) {
                val android = project.extensions.getByName("android") as com.android.build.gradle.BaseExtension
                android.compileSdkVersion(36)
                android.defaultConfig {
                    minSdkVersion(21)
                    targetSdkVersion(36)
                }
            }
        } else {
            project.afterEvaluate {
                if (hasProperty("android")) {
                    val android = extensions.getByName("android") as com.android.build.gradle.BaseExtension
                    android.compileSdkVersion(36)
                    android.defaultConfig {
                        minSdkVersion(21)
                        targetSdkVersion(36)
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
