import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.juicessh.juice_ssh_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // `flutter_local_notifications` 鐟曚焦鐪板鈧崥?core library desugaring閿?
        // 閸氾箑鍨?`:app:checkDebugAarMetadata` 娴兼氨娲块幒銉ャ亼鐠愩儯鈧?
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 濞夈劍鍓伴敍姘崇箹闁?*閺佸懏鍓?*娑撳秵鏁奸幋鎰斧閻楀牏娈?`com.sonelli.juicessh`閵?
        // 娣囨繃瀵旀稉宥呮倱閻?applicationId閿涘本澧犻懗鑺ュΩ閸樼喓澧?APK 娑撳孩婀版径宥呭煝閸氬本妞傜憗鍛躬
        // 閸氬奔绔撮崣鎷岊啎婢跺洣绗傞崑姘垛偓鎰潌鐎靛湱鍙庨敍鍫㈩劮閸氬秳绗夐崥灞肩瘍閺冪姵纭舵禍鎺旀祲鐟曞棛娲婄€瑰顥婇敍澶堚偓?
        applicationId = "com.juicessh.juice_ssh_flutter"
        // 閸樼喓澧?`AndroidManifest.xml` 閻?minSdk 閺?26閿涘矁绻栭柌灞筋嚠姒绘劑鈧?
        minSdk = 26
        // 閸樼喓澧?apktool.yml 闁?targetSdkVersion 閺?29閿涘牅绗夐弰?Flutter 姒涙顓婚惃?36閿涘鈧?
        // targetSdk 閸愬啿鐣炬稉鈧径褎澹掓潻鎰攽閺冩儼顢戞稉鐚寸礉娑撹桨绨℃稉?1:1 鐎靛綊缍堢挧鐤潌閺勬儳绱￠崘娆愵劥 29閵?
        targetSdk = 29
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 姝ｅ紡鍙戝竷绛惧悕锛堢 322 杞級锛氫粠 android/key.properties 璇诲彇锛?    // 璇ユ枃浠朵笌 .jks 閮戒笉杩?git銆傛枃浠剁己澶辨椂鍥為€€ debug 绛惧悕锛屼繚璇佹瀯寤轰笉涓柇銆?    val juiceKeyProps = Properties().apply {
        val kp = rootProject.file("key.properties")
        if (kp.exists()) kp.inputStream().use { load(it) }
    }
    signingConfigs {
        create("release") {
            if (juiceKeyProps.getProperty("storeFile") != null) {
                storeFile = file(juiceKeyProps.getProperty("storeFile"))
                storePassword = juiceKeyProps.getProperty("storePassword")
                keyAlias = juiceKeyProps.getProperty("keyAlias")
                keyPassword = juiceKeyProps.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = if (juiceKeyProps.getProperty("storeFile") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    lint {
        // 閻╊喗鐖?API 29 娑?Google Play 閻ㄥ嫪绗傞弸鎯邦洣濮瑰偊绱?3+閿涘鍟跨粣渚婄礉鏉╂瑦娼?lint 濡偓閺屻儱婀?
        // release 閺嬪嫬缂撻柌灞炬Ц error 缁狙嶇礉娴兼氨娲块幒銉よ厬閺傤厽澧﹂崠鍛偓鍌涙拱婢跺秴鍩㈤崣顏勪粵閺堫剙婀寸€瑰顥婃稉搴ㄢ偓鎰潌
        // 鐎靛湱鍙庨妴浣风瑝娑撳﹥鐏﹂敍灞芥礈濮濄倖妯夊蹇撳彠閹哄鐣犻敍鍫濆斧閻?JuiceSSH 閺堫剝闊╃亸杈ㄦЦ targetSdk 29閿涘鈧?
        disable += "ExpiredTargetSdkVersion"
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // 闁板秴鎮庢稉濠囨桨閻?isCoreLibraryDesugaringEnabled閵?
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
