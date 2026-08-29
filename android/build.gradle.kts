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

// 部分插件(file_picker 依赖链 flutter_plugin_android_lifecycle)要求 compileSdk>=36，
// 将其应用到所有 Android 插件子模块，避免 AAR metadata 校验失败。
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android")
        if (android is com.android.build.api.dsl.CommonExtension) {
            android.compileSdk = 36
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
