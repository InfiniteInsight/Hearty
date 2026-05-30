plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.hearty.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.hearty.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // sherpa_onnx (TTS) and onnxruntime-android (wake word) both ship a
    // libonnxruntime.so with the same soname → duplicate-merge conflict, so we
    // keep one. The wake word reaches ORT through the Java API whose JNI shim
    // (libonnxruntime4j_jni.so) imports a VERSION-TAGGED symbol
    // OrtGetApiBase@VERS_<ver>, so the onnxruntime-android version below MUST
    // equal the ORT version sherpa bundles (1.24.3) or it fails to link.
    // NOTE (follow-up hardening): pickFirst leaves which libonnxruntime.so wins
    // arbitrary. Long-term, resolve to a single runtime explicitly.
    packaging {
        jniLibs {
            pickFirsts += "**/libonnxruntime.so"
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Must match the ORT version bundled by sherpa_onnx_android (1.24.3) — see
    // the packaging{} comment above re: the version-tagged OrtGetApiBase symbol.
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.24.3")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
}
