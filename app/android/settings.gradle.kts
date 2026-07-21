pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    // Flutter plugin modules (shared_preferences_android, and later the
    // firebase_* packages) are Android LIBRARIES, not applications, so they
    // apply com.android.library. Without a version declared here, an IDE
    // configuring those subprojects on its own cannot resolve the plugin and
    // fails with "Plugin [id: 'com.android.library'] was not found in any of
    // the following sources". Must stay on the same AGP version as
    // com.android.application above.
    id("com.android.library") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
