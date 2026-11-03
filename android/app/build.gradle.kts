import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Missing or damaged release credentials must not prevent IDE sync or Debug.
// Validation belongs to the Release task graph, never to requested task names.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val signingPropertiesReadable = runCatching {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}.isSuccess
if (!signingPropertiesReadable) keystoreProperties.clear()
val missingSigningFields = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
    .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
val releaseStoreFile = keystoreProperties.getProperty("storeFile")
    ?.takeIf { it.isNotBlank() }
    ?.let { runCatching { rootProject.file(it) }.getOrNull() }

val validateReleaseSigningConfiguration = tasks.register("validateReleaseSigningConfiguration") {
    group = "verification"
    description = "Require private signing material for Release without a Debug fallback."
    doLast {
        check(keystorePropertiesFile.isFile) {
            "Release signing requires android/key.properties. Debug does not require it."
        }
        check(signingPropertiesReadable) {
            "Release signing could not read android/key.properties."
        }
        check(missingSigningFields.isEmpty()) {
            "Release signing is missing fields: ${missingSigningFields.joinToString()}."
        }
        check(releaseStoreFile?.isFile == true) {
            "Release signing keystore is missing or invalid; check storeFile in android/key.properties."
        }
    }
}

android {
    // flutter-release-publisher: signing-start
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = releaseStoreFile
            storePassword = keystoreProperties.getProperty("storePassword")
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

androidComponents.onVariants(androidComponents.selector().withBuildType("release")) { variant ->
    val suffix = variant.name.replaceFirstChar { it.uppercaseChar() }
    tasks.matching {
        it.name == "pre${suffix}Build" || it.name == "validateSigning$suffix"
    }.configureEach {
        dependsOn(validateReleaseSigningConfiguration)
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
