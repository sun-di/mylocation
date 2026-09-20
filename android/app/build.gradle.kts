plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.showlocation"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.showlocation"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 高德整合包（3D 地图 + 定位 + 搜索）。
    // 用于 AL 探针：AMapLocationClient 拿"高德视角加工后"的位置（map-matching / 反 mock / 多源融合）。
    //
    // 为什么这里要显式声明：
    //  - csp_amap_flutter_map 插件用 implementation 依赖这个整合包，不外泄给 app 模块，
    //    导致 app 模块 import com.amap.api.location.* 时报 Unresolved reference；
    //  - 整合包内部已内嵌定位类（不是传递依赖），所以不能单独加 com.amap.api:location，
    //    否则会和整合包内嵌的类重复冲突（Duplicate class）。
    //  - 直接依赖同一个整合包即可：既能看到定位类，又不会重复。
    implementation("com.amap.api:3dmap-location-search:10.1.200_loc6.4.9_sea9.7.4")
}
