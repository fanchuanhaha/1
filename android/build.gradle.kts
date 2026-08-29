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
// 注意: evaluationDependsOn(":app") 会让 :app 预先求值，此时不能再调 afterEvaluate，
// 因此按项目是否已求值分两种情况设置。已求值的模块直接赋值，未求值的挂 afterEvaluate。
subprojects {
    fun applyCompileSdk(prj: Project) {
        val android = prj.extensions.findByName("android")
        if (android is com.android.build.api.dsl.CommonExtension) {
            android.compileSdk = 36
        }
    }
    if (project.state.executed) {
        applyCompileSdk(project)
    } else {
        afterEvaluate {
            applyCompileSdk(project)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
