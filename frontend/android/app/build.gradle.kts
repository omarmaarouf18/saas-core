import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") apply false
}

// PUSH-FCM: google-services.json (Firebase project config) is never
// committed; CI writes it from a secret. Without it the app still builds
// and runs with push disabled (docs/PUSH.md).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn("PUSH-FCM: android/app/google-services.json not found; push disabled in this build")
}

// STORE-PIPELINE: the Play upload key. Read from android/key.properties
// (local, never committed) or from the environment (CI writes the keystore
// from a secret). Keys: storeFile, storePassword, keyAlias, keyPassword /
// ANDROID_KEYSTORE_PATH, ANDROID_KEYSTORE_PASSWORD, ANDROID_KEY_ALIAS,
// ANDROID_KEY_PASSWORD. Without them, release builds keep the debug key, so
// the GitHub-release APK channel (build-apk.yml) is unchanged. Store builds
// set WADDIFY_REQUIRE_UPLOAD_KEY=true and fail instead of shipping a
// debug-signed bundle (frontend/docs/STORE_TESTING.md).
val uploadKey: Map<String, String?> = run {
    val props = Properties()
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { props.load(it) }
    mapOf(
        "storeFile" to (props.getProperty("storeFile") ?: System.getenv("ANDROID_KEYSTORE_PATH")),
        "storePassword" to (props.getProperty("storePassword") ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")),
        "keyAlias" to (props.getProperty("keyAlias") ?: System.getenv("ANDROID_KEY_ALIAS")),
        "keyPassword" to (props.getProperty("keyPassword") ?: System.getenv("ANDROID_KEY_PASSWORD")),
    )
}
val hasUploadKey = uploadKey.values.all { !it.isNullOrBlank() } &&
    file(uploadKey.getValue("storeFile")!!).exists()
if (!hasUploadKey && System.getenv("WADDIFY_REQUIRE_UPLOAD_KEY") == "true") {
    throw GradleException(
        "STORE-PIPELINE: WADDIFY_REQUIRE_UPLOAD_KEY=true but the upload keystore is missing " +
            "or incomplete (ANDROID_KEYSTORE_PATH / _PASSWORD / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD)",
    )
}

android {
    namespace = "com.saascore.frontend"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (PUSH-FCM) uses java.time APIs.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Each product flavor below sets its own applicationId (ADR-0030).
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // SPLIT-APPS (ADR-0030): one codebase, three apps. Every Android build
    // names its flavor (--flavor customer|console|employees) and passes the
    // same value as --dart-define=APP_CLIENT. The launcher name comes from
    // src/<flavor>/res/values/strings.xml (app_name).
    flavorDimensions += "client"
    productFlavors {
        create("customer") {
            dimension = "client"
            applicationId = "app.waddify"
        }
        create("console") {
            dimension = "client"
            applicationId = "app.waddify.console"
        }
        create("employees") {
            dimension = "client"
            applicationId = "app.waddify.employees"
        }
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(uploadKey.getValue("storeFile")!!)
                storePassword = uploadKey.getValue("storePassword")
                keyAlias = uploadKey.getValue("keyAlias")
                keyPassword = uploadKey.getValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // STORE-PIPELINE: upload key when configured (see above), else the
            // debug key so `flutter run --release` and the APK channel work.
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
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
    // Pinned: the version flutter_local_notifications 22.x documents.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
