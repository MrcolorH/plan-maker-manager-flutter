import com.android.build.gradle.LibraryExtension

allprojects {
    repositories {
        // 本地 Maven 镜像：热点网络下 GCS (storage.googleapis.com) TLS 握手不稳，
        // 将 Flutter 引擎 AAR 预下载到 .local-maven-repo，Gradle 优先命中本地，避免网络抖动
        maven { url = uri("${rootProject.projectDir}/.local-maven-repo") }
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

// file_picker 等旧插件硬编码 compileSdk 34，而 flutter_plugin_android_lifecycle 的
// AAR metadata 要求依赖方 compileSdk >= 36；此处对所有插件(library)模块强制提升，
// 无需改动插件源码，插件未来升级到 36 后此配置自动失效
subprojects {
    if (state.executed) {
        // 项目已评估完成（evaluationDependsOn 导致的提前评估），直接修改，避免 afterEvaluate 抛错
        extensions.findByType(LibraryExtension::class.java)?.let { lib ->
            if ((lib.compileSdk ?: 0) < 36) {
                lib.compileSdk = 36
            }
        }
    } else {
        afterEvaluate {
            extensions.findByType(LibraryExtension::class.java)?.let { lib ->
                if ((lib.compileSdk ?: 0) < 36) {
                    lib.compileSdk = 36
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
