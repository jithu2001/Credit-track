import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (gitignored; see key.properties.example
// and README "Release builds"). Debug builds and `flutter test` don't need it.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }

// `-P wfLocal=true` only makes sense for debug builds (see below).
val local = project.hasProperty("wfLocal")

// A release build (assemble/bundle…Release) fails early, with a clear message,
// instead of silently producing an app signed with the debug key.
val buildsRelease = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (buildsRelease) {
    if (local) {
        throw GradleException("wfLocal is for debug builds only. Drop --android-project-arg wfLocal=true for a release build.")
    }
    if (!hasReleaseKeystore) {
        throw GradleException(
            "Release signing is not set up: android/key.properties is missing. " +
                "Copy android/key.properties.example to android/key.properties and fill it in " +
                "(wholeflow_app/README.md, \"Release builds\")."
        )
    }
    for (key in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        if (keystoreProperties.getProperty(key).isNullOrBlank()) {
            throw GradleException("android/key.properties has no $key (see key.properties.example).")
        }
    }
}

android {
    namespace = "com.wholeflow.wholeflow_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.wholeflow.wholeflow_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appName"] = "WholeFlow"
    }

    // `-P wfLocal=true` (flutter build … --android-project-arg wfLocal=true): a debug
    // build for testing against a WholeFlow server on this computer, installed
    // beside the real apps (own id and name) so they and their sign-ins stay
    // untouched. Refused for release builds (above).
    flavorDimensions += listOf("role")
    productFlavors {
        create("owner") {
            dimension = "role"
            // Keeps the v0.3.0 id so existing installs update in place to the Owner app.
            applicationId = "com.wholeflow.wholeflow_app"
            manifestPlaceholders["appName"] = if (local) "WF Local Owner" else "WholeFlow Owner"
        }
        create("staff") {
            dimension = "role"
            applicationId = "com.wholeflow.staff"
            manifestPlaceholders["appName"] = if (local) "WF Local Staff" else "WholeFlow Staff"
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                // storeFile is relative to android/app (or absolute).
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            if (local) applicationIdSuffix = ".local"
        }
        release {
            // The upload key from key.properties; Google Play re-signs with the
            // app signing key (Play App Signing). Never the debug key.
            if (hasReleaseKeystore) signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
