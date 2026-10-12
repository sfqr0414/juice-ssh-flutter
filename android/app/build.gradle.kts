import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式发布签名（第 325 轮）：数值取自 android/key.properties，
// 该文件与 .jks 都不进 git。文件缺失时回退 debug 签名，
// 保证任何没有发布密钥的机器依然能构建。
val juiceKeyProps = Properties().apply {
    val juiceKeyFile = rootProject.file("key.properties")
    if (juiceKeyFile.exists()) juiceKeyFile.inputStream().use { load(it) }
}
val juiceHasReleaseKey = juiceKeyProps.getProperty("storeFile") != null

android {
    namespace = "com.juicessh.juice_ssh_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // `flutter_local_notifications` 要求开启 core library desugaring，
        // 否则 `:app:checkDebugAarMetadata` 会直接失败。
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 注意：这里**故意**不改成原版的 `com.sonelli.juicessh`。
        // 保持不同的 applicationId，才能把原版 APK 与本复刻同时装在
        // 同一台设备上做逐屏对照（签名不同也无法互相覆盖安装）。
        applicationId = "com.juicessh.juice_ssh_flutter"
        // 原版 `AndroidManifest.xml` 的 minSdk 是 26，这里对齐。
        minSdk = 26
        // 原版 apktool.yml 里 targetSdkVersion 是 29（不是 Flutter 默认的 36）。
        // targetSdk 决定一大批运行时行为，为了与 1:1 对齐起见显式写死 29。
        targetSdk = 29
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (juiceHasReleaseKey) {
                storeFile = file(juiceKeyProps.getProperty("storeFile"))
                storePassword = juiceKeyProps.getProperty("storePassword")
                keyAlias = juiceKeyProps.getProperty("keyAlias")
                keyPassword = juiceKeyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 有 release keystore 就用正式签名，否则回退 debug（见文件顶部说明）。
            signingConfig = if (juiceHasReleaseKey) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }

    lint {
        // 目标 API 29 与 Google Play 的上架要求（33+）冲突，这条 lint 检查在
        // release 构建里是 error 级，会直接中断打包。本复刻只做本地安装与逐屏
        // 对照、不上架，因此显式关掉它（原版 JuiceSSH 本身就是 targetSdk 29）。
        disable += "ExpiredTargetSdkVersion"
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // 配合上面的 isCoreLibraryDesugaringEnabled。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
