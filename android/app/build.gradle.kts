import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase Cloud Messaging — reads google-services.json (multi-app: prod + .staging).
    id("com.google.gms.google-services")
}

// Release signing is loaded from android/key.properties (gitignored — never committed).
// If that file is absent (e.g. a dev machine without the upload keystore), the release
// build falls back to debug signing so `flutter run --release` still works locally.
// See ANDROID.md §A and key.properties.example for setup.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// AdMob Android app id, injected into the manifest's ads APPLICATION_ID
// meta-data placeholder (${admobAppId}). Resolution order:
//   1. -PADMOB_ANDROID_APP_ID=… (Gradle property / CI)
//   2. admobAppId=… in android/key.properties (gitignored; see key.properties.example)
//   3. ADMOB_ANDROID_APP_ID env var
//   4. Google's PUBLIC TEST app id (default) — safe placeholder so the SDK
//      provider doesn't crash; serves no real ads. See DEPLOYMENT.md.
val admobAppId: String =
    (project.findProperty("ADMOB_ANDROID_APP_ID") as String?)
        ?: (keystoreProperties["admobAppId"] as String?)
        ?: System.getenv("ADMOB_ANDROID_APP_ID")
        ?: "ca-app-pub-3940256099942544~3347511713"

android {
    namespace = "com.rohanchari.steptracker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (uses java.time APIs that need
        // backporting on minSdk 28). See ANDROID.md §B and the plugin README.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Matches the iOS prod bundle id (Bara). Permanent on the Play Store once published.
        applicationId = "com.rohanchari.steptracker"
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Injected into AndroidManifest.xml's AdMob APPLICATION_ID meta-data.
        // Defaults to Google's public test app id (see above) until a real
        // Android AdMob app id is supplied at build time.
        manifestPlaceholders["admobAppId"] = admobAppId
    }

    // Mirror the iOS two-listing model (see DEPLOYMENT.md): build with
    //   flutter build appbundle --flavor prod    --dart-define=BACKEND_BASE_URL=https://steptracker-api.org
    //   flutter build appbundle --flavor staging --dart-define=BACKEND_BASE_URL=https://staging.steptracker-api.org
    // NOTE: because flavors are defined, Android builds/runs MUST pass --flavor prod|staging
    // (unlike the bare `flutter run` used for iOS in DEPLOYMENT.md).
    flavorDimensions += "env"
    productFlavors {
        create("prod") {
            dimension = "env"
            // applicationId stays com.rohanchari.steptracker → iOS "Bara"
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging" // → com.rohanchari.steptracker.staging → iOS "Bara Staging"
            versionNameSuffix = "-staging"
        }
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Fallback so `flutter run --release` works before the upload keystore exists.
                // A Play-uploadable .aab REQUIRES key.properties to be present.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Backports java.time etc. for core library desugaring (flutter_local_notifications).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // Phase 2 — background step sync. WorkManager runs the periodic CoroutineWorker;
    // connect-client lets that worker read Health Connect from the background. The
    // connect-client version is pinned to match the `health` Flutter plugin
    // (health-13.3.1 -> 1.2.0-alpha02) so Gradle doesn't resolve two versions.
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    implementation("androidx.health.connect:connect-client:1.2.0-alpha02")
    // Play Install Referrer — deterministic, silent referral attribution for
    // installs from the Play Store (reads the &referrer= we bake into the store
    // URL on the /r/ landing page). Referral feature; see InstallAttributionService.
    implementation("com.android.installreferrer:installreferrer:2.2")
}
