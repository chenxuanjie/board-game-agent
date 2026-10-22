import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // flutter-release-publisher: signing-start
    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    // flutter-release-publisher: signing-end

    namespace = "com.example.boardgameagent"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.boardgameagent"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

// Validate merged Flutter assets for every Android build, including debug.
// Documents stay on NAS; never strip an already signed APK after compilation.
tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }.configureEach {
    doLast {
        val forbidden = outputs.files.asFileTree.matching {
            include("**/flutter_assets/assets/games/*/docs/**")
            include("**/flutter_assets/**/*.pdf")
            for (extension in listOf("md", "txt", "html", "htm", "zip", "7z", "rar", "epub", "doc", "docx")) {
                include("**/flutter_assets/assets/games/**/*.$extension")
            }
        }.files
        check(forbidden.isEmpty()) {
            "Android APK must not bundle game documents: " +
                forbidden.take(10).joinToString { it.name } +
                ". Exclude Android from document assets in pubspec.yaml."
        }
    }
}
