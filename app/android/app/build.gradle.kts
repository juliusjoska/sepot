import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// FCM je volitelný (opt-in „fast mode"). Výchozí doručování běží na
// UnifiedPush a Firebase nepotřebuje. Plugin google-services proto
// aplikujeme jen když si dodáš vlastní google-services.json (zkopíruj
// google-services.json.example a doplň svůj Firebase projekt). Bez něj
// se Firebase do buildu nezahrne a appka běží dál — jen bez FCM.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Release podpis: heslo/alias v android/key.properties (mimo git, záloha
// v bezpečném úložišti mimo repo). Když soubor chybí (CI/cizí checkout),
// spadneme zpět na debug podpis, aby `flutter run` fungoval.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
if (hasReleaseSigning) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "cz.sepot.sepot"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications vyžaduje java.time API na starších API levelech
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "cz.sepot.sepot"
        // libsignal binárky vyžadují Android 7.0+ (API 24)
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // storeFile v key.properties je relativní k android/ (rootProject)
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // fallback pro checkout bez keystore (nešiřitelný do storu)
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

// UnifiedPush webpush vrstva táhne JVM `com.google.crypto.tink:tink`, který
// koliduje s `tink-android` (z flutter_secure_storage) — duplicitní třídy,
// build padá. Necháme jen android variantu (obsahuje stejné třídy).
configurations.all {
    exclude(group = "com.google.crypto.tink", module = "tink")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
