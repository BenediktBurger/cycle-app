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

// Byte-identical libdartjni.so across build hosts: the jni plugin builds
// libdartjni.so from C sources at build time and the NDK's CMake toolchain
// appends `-Wl,--build-id=sha1` to its linker flags. The resulting
// .note.gnu.build-id hashes the pre-strip debug info, which encodes absolute
// toolchain paths (ANDROID_HOME etc.) that differ between build hosts — the
// paths never survive into the stripped output, but the build-id does,
// breaking byte-identical .so comparison between GitHub CI and the F-Droid
// buildserver. Suppressing the note via `--build-id=none` removes that
// environment dependency. It must land after the toolchain's build-id flag,
// because the last `--build-id` linker option wins; CMAKE_SHARED_LINKER_FLAGS
// guarantees this order since the NDK toolchain composes
// "<its flags> <this cache variable>", and jni's android/build.gradle sets
// no CMake arguments of its own (only the CmakeLists path), so nothing gets
// overwritten. Scoped to the jni plugin's defaultConfig so it applies to
// every variant; the other shipped native libraries (libapp.so, libflutter.so,
// libsqlite3.so) are prebuilt/native-assets artifacts whose AOT/artifact
// output is unaffected by linker arguments here. The jni subproject is
// configured dynamically (Groovy builder) because its android extension is
// the classic DSL ("android.newDsl=false" gradle property), which is not
// statically typeable here without importing AGP internals.
subprojects {
    if (name == "jni") {
        val jniSubproject = this
        plugins.withId("com.android.library") {
            jniSubproject.withGroovyBuilder {
                "android" {
                    "defaultConfig" {
                        "externalNativeBuild" {
                            "cmake" {
                                "arguments"("-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--build-id=none")
                            }
                        }
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
