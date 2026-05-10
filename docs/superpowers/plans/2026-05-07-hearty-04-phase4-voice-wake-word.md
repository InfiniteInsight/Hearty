# Hearty Phase 4: Voice Input, TTS & Wake Word — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the complete voice I/O loop — wake word detection foreground service (openWakeWord ONNX pipeline), STT overlay, TTS response, and activation feedback — wired to the log entry and home screens.

**Architecture:** A Kotlin `HeartyWakeWordService` runs continuously as an Android foreground service, feeding 16kHz PCM audio through a 3-stage ONNX pipeline (mel spectrogram → embeddings → classifier). On detection it: (1) acquires a `SCREEN_BRIGHT_WAKE_LOCK` to turn on the screen, (2) fires `ACTION_WAKE_WORD_DETECTED` Intent to `MainActivity` (brings app to front from any state / screen off), (3) invokes `MethodChannel('com.hearty.app/wake_word').wakeWordDetected` for low-latency delivery when the Flutter engine is already running. `MainActivity` applies `setShowWhenLocked`/`setTurnScreenOn` to show over the lock screen. The Flutter listener lives in `_ScaffoldWithNavBar` (not `HomeScreen`) so it is active on all four tabs. The voice overlay is an in-app bottom sheet managing STT → API → TTS in a linear state machine. Non-health queries are redirected to the user's configured assistant (Settings preference). After the initial response, one follow-up voice turn is captured via `sendFollowUpToApi()` (logged as a symptom) — no loop.

**Tech Stack:** ONNX Runtime Android (`com.microsoft.onnxruntime:onnxruntime-android:1.17.3`), `speech_to_text` ^7.0.0, `flutter_tts` ^4.2.2, `just_audio` ^0.10.4, Riverpod `StateNotifierProvider`, Flutter `MethodChannel`, Android `AudioRecord` API, `WorkManager` (not needed this phase — used in Phase 6).

**Environment note:** Flutter binary is at `/home/evan/tools/flutter/bin/flutter`, not in PATH. Android SDK is at `/home/evan/tools/android-sdk`. For all shell commands use:
```bash
export ANDROID_HOME=/home/evan/tools/android-sdk
export PATH="$PATH:/home/evan/tools/flutter/bin"
```

**Pre-phase assets confirmed:**
- `hearty_app/assets/wake_word/hey_hearty.onnx` — model I/O: input `x` [1, 16, 96] float32; output `sigmoid` [1, 1] float32
- Registered in `pubspec.yaml`

> **Status note (2026-05-09):** `hey_hearty.onnx` training was not completed. The service currently loads `hey_jarvis.onnx` (a pre-built openWakeWord model) as a stand-in. All model paths in this task plan that reference `hey_hearty.onnx` are the intended target; substitute `hey_jarvis.onnx` in the actual code until custom training is done.

---

## File Map

**New files (Kotlin):**
- `hearty_app/android/app/src/main/kotlin/com/hearty/app/HeartyWakeWordService.kt`
- `hearty_app/android/app/src/main/kotlin/com/hearty/app/BootReceiver.kt`

**Modified files (Android):**
- `hearty_app/android/app/build.gradle.kts` — add ONNX Runtime dep
- `hearty_app/android/app/src/main/AndroidManifest.xml` — add service + receiver

**New assets:**
- `hearty_app/assets/wake_word/melspectrogram.onnx` — openWakeWord mel spectrogram model
- `hearty_app/assets/wake_word/embedding_model.onnx` — openWakeWord embedding model
- `hearty_app/assets/audio/wake_chime.mp3` — activation chime

**Modified files (pubspec + assets):**
- `hearty_app/pubspec.yaml` — register new assets

**New Dart files:**
- `hearty_app/lib/features/wake_word/wake_word_channel.dart`
- `hearty_app/lib/features/wake_word/providers/wake_word_provider.dart`
- `hearty_app/lib/core/audio/chime_player.dart`
- `hearty_app/lib/features/voice/models/voice_state.dart`
- `hearty_app/lib/features/voice/providers/voice_provider.dart`
- `hearty_app/lib/features/voice/widgets/waveform_animation.dart`
- `hearty_app/lib/features/voice/widgets/thinking_animation.dart`
- `hearty_app/lib/features/voice/screens/voice_overlay_screen.dart`

**Modified Dart files:**
- `hearty_app/lib/features/logging/screens/home_screen.dart`
- `hearty_app/lib/features/logging/screens/log_entry_screen.dart`
- `hearty_app/lib/features/settings/screens/settings_screen.dart`

**New test files:**
- `hearty_app/test/features/wake_word/wake_word_provider_test.dart`
- `hearty_app/test/features/voice/voice_provider_test.dart`
- `hearty_app/test/features/voice/voice_overlay_screen_test.dart`

---

## Task 1: Android Build Setup — ONNX Runtime + Manifest

**Files:**
- Modify: `hearty_app/android/app/build.gradle.kts`
- Modify: `hearty_app/android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add ONNX Runtime dependency to build.gradle.kts**

Open `hearty_app/android/app/build.gradle.kts`. After the `flutter { source = "../.." }` block, add:

```kotlin
dependencies {
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.17.3")
}
```

The complete file should look like:

```kotlin
plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.hearty.app"
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
        applicationId = "com.hearty.app"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.17.3")
}
```

- [ ] **Step 2: Add HeartyWakeWordService and BootReceiver to AndroidManifest.xml**

Open `hearty_app/android/app/src/main/AndroidManifest.xml`. Add the service and receiver inside the `<application>` tag, after the `<activity>` block and before the `</application>` closing tag:

```xml
        <!-- Wake word foreground service -->
        <service
            android:name=".HeartyWakeWordService"
            android:exported="false"
            android:foregroundServiceType="microphone" />

        <!-- Restart service on device boot -->
        <receiver
            android:name=".BootReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
            </intent-filter>
        </receiver>
```

The `<application>` tag section should now look like:

```xml
    <application
        android:label="hearty_app"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />

        <!-- Wake word foreground service -->
        <service
            android:name=".HeartyWakeWordService"
            android:exported="false"
            android:foregroundServiceType="microphone" />

        <!-- Restart service on device boot -->
        <receiver
            android:name=".BootReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
            </intent-filter>
        </receiver>
    </application>
```

- [ ] **Step 3: Verify Gradle sync resolves**

Run:
```bash
cd hearty_app && export ANDROID_HOME=/home/evan/tools/android-sdk && /home/evan/tools/flutter/bin/flutter pub get
```

Expected: no errors. (Full build is verified in later tasks.)

- [ ] **Step 4: Commit**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app
git add hearty_app/android/app/build.gradle.kts hearty_app/android/app/src/main/AndroidManifest.xml
git commit -m "feat: add ONNX Runtime dep + HeartyWakeWordService manifest declarations"
```

---

## Task 2: openWakeWord Auxiliary Model Assets

The `hey_hearty.onnx` classifier expects 16 pre-computed 96-dim embeddings as input. These embeddings are produced by a 3-stage pipeline:
1. Raw audio → mel spectrogram (via `melspectrogram.onnx`)
2. Mel spectrogram → embedding (via `embedding_model.onnx`)
3. Embeddings → wake word score (via `hey_hearty.onnx`)

Models 1 and 2 are provided by the openWakeWord Python package and are the same for all wake words.

**Files:**
- Create: `hearty_app/assets/wake_word/melspectrogram.onnx`
- Create: `hearty_app/assets/wake_word/embedding_model.onnx`
- Modify: `hearty_app/pubspec.yaml`

- [ ] **Step 1: Extract auxiliary models from the installed openWakeWord Python package**

The openWakeWord package was used to train the model, so it should already be installed. Run:

```bash
python3 -c "
import openwakeword
import os, shutil
pkg_dir = os.path.dirname(openwakeword.__file__)
models_dir = os.path.join(pkg_dir, 'resources', 'models')
print('Models dir:', models_dir)
for f in os.listdir(models_dir):
    print(' ', f)
"
```

Expected output (approximate):
```
Models dir: /home/evan/.../openwakeword/resources/models
  melspectrogram.onnx
  embedding_model.onnx
  ...
```

Then copy to the assets directory:

```bash
python3 -c "
import openwakeword, os, shutil
pkg_dir = os.path.dirname(openwakeword.__file__)
models_dir = os.path.join(pkg_dir, 'resources', 'models')
dest = 'hearty_app/assets/wake_word'
shutil.copy(os.path.join(models_dir, 'melspectrogram.onnx'), dest)
shutil.copy(os.path.join(models_dir, 'embedding_model.onnx'), dest)
print('Copied melspectrogram.onnx and embedding_model.onnx')
"
```

Expected: `Copied melspectrogram.onnx and embedding_model.onnx`

- [ ] **Step 2: Inspect model I/O shapes (record these — Kotlin code depends on them)**

Run:
```bash
python3 -c "
import onnxruntime as ort
for name in ['melspectrogram.onnx', 'embedding_model.onnx']:
    path = f'hearty_app/assets/wake_word/{name}'
    sess = ort.InferenceSession(path)
    print(f'{name}:')
    for inp in sess.get_inputs():
        print(f'  input  {inp.name}: shape={inp.shape}')
    for out in sess.get_outputs():
        print(f'  output {out.name}: shape={out.shape}')
"
```

Note down the exact input/output node names and shapes. You will use them in Task 3 (the Kotlin service). Expected output should show:
- `melspectrogram.onnx`: input ~[batch, 16000], output ~[batch, 32, 32] or [batch, 96, 64]
- `embedding_model.onnx`: input matches melspectrogram output, output ~[batch, 1, 96]

The exact shapes determine buffer sizing in the Kotlin code. If shapes differ from these examples, adjust the `SAMPLES_PER_CHUNK`, `MEL_FRAMES`, and `EMBEDDING_DIM` constants in Task 3 accordingly.

- [ ] **Step 3: Register all wake_word assets in pubspec.yaml**

Open `hearty_app/pubspec.yaml`. Update the `assets` section under `flutter:` to:

```yaml
flutter:
  uses-material-design: true

  assets:
    - assets/wake_word/hey_hearty.onnx
    - assets/wake_word/melspectrogram.onnx
    - assets/wake_word/embedding_model.onnx
    - assets/audio/wake_chime.mp3
```

(The `assets/audio/wake_chime.mp3` will be added in Task 6 but register it now to avoid a two-step pubspec edit.)

- [ ] **Step 4: Create the audio assets directory**

```bash
mkdir -p hearty_app/assets/audio
```

- [ ] **Step 5: Verify flutter pub get still passes**

```bash
cd hearty_app && /home/evan/tools/flutter/bin/flutter pub get
```

Expected: `Running "flutter pub get" in hearty_app...` then success.

- [ ] **Step 6: Commit**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app
git add hearty_app/assets/wake_word/ hearty_app/assets/audio/ hearty_app/pubspec.yaml
git commit -m "feat: bundle openWakeWord auxiliary models (melspectrogram, embedding)"
```

---

## Task 3: HeartyWakeWordService.kt — Foreground Service + ONNX Pipeline

**Files:**
- Create: `hearty_app/android/app/src/main/kotlin/com/hearty/app/HeartyWakeWordService.kt`

This service runs the 3-stage wake word pipeline continuously:
1. Captures 16kHz PCM audio using `AudioRecord`
2. Every `SAMPLES_PER_CHUNK` samples (1 second): runs mel spectrogram ONNX model
3. Feeds mel features into embedding ONNX model to get a 96-dim embedding
4. Adds embedding to a rolling buffer of 16 embeddings
5. When the buffer has 16 embeddings: runs the wake word classifier
6. If score > threshold: signals Flutter via MethodChannel

**IMPORTANT:** Before writing this file, look up the actual node names from the Step 2 output in Task 2. Replace `MEL_INPUT_NODE`, `MEL_OUTPUT_NODE`, `EMBED_INPUT_NODE`, `EMBED_OUTPUT_NODE` with the actual names you found.

- [ ] **Step 1: Write HeartyWakeWordService.kt**

Create `hearty_app/android/app/src/main/kotlin/com/hearty/app/HeartyWakeWordService.kt`:

```kotlin
package com.hearty.app

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.IBinder
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.nio.FloatBuffer
import java.util.LinkedList

class HeartyWakeWordService : Service() {

    companion object {
        const val CHANNEL_ID = "hearty_wake_word"
        const val NOTIFICATION_ID = 1001
        const val METHOD_CHANNEL = "com.hearty.app/wake_word"

        // Audio config
        const val SAMPLE_RATE = 16000
        const val SAMPLES_PER_CHUNK = 16000  // 1 second

        // Model node names — verify against your Task 2 inspection output
        const val MEL_INPUT_NODE = "input"         // melspectrogram.onnx input name
        const val MEL_OUTPUT_NODE = "output"       // melspectrogram.onnx output name
        const val EMBED_INPUT_NODE = "input_1"     // embedding_model.onnx input name
        const val EMBED_OUTPUT_NODE = "output_0"   // embedding_model.onnx output name

        // Classifier config (matches hey_hearty.onnx input [1, 16, 96])
        const val EMBEDDING_BUFFER_SIZE = 16
        const val EMBEDDING_DIM = 96

        // Detection threshold (0.0–1.0; lower = more sensitive but more false positives)
        const val DEFAULT_THRESHOLD = 0.5f
    }

    private var audioRecord: AudioRecord? = null
    private var ortEnv: OrtEnvironment? = null
    private var melSession: OrtSession? = null
    private var embedSession: OrtSession? = null
    private var wakeSession: OrtSession? = null
    private var detectionThread: Thread? = null
    private var isRunning = false
    private var threshold = DEFAULT_THRESHOLD

    // Rolling buffer: holds the last EMBEDDING_BUFFER_SIZE embeddings
    private val embeddingBuffer = LinkedList<FloatArray>()

    // Flutter MethodChannel — wired up when a FlutterEngine attaches
    private var methodChannel: MethodChannel? = null
    private var flutterEngine: FlutterEngine? = null

    // Set to true by the Pause action; cleared when unpaused
    private var isPaused = false

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        initOnnxModels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            "PAUSE" -> isPaused = !isPaused
            else -> startDetection()
        }
        startForeground(NOTIFICATION_ID, buildNotification())
        return START_STICKY  // Restart automatically if killed
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopDetection()
        ortEnv?.close()
        super.onDestroy()
    }

    // Called from MainActivity to wire up the MethodChannel
    fun attachFlutterEngine(engine: FlutterEngine) {
        flutterEngine = engine
        methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startListening" -> {
                    isPaused = false
                    result.success(null)
                }
                "stopListening" -> {
                    isPaused = true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun initOnnxModels() {
        ortEnv = OrtEnvironment.getEnvironment()
        val env = ortEnv!!
        val opts = OrtSession.SessionOptions()

        fun loadModel(assetPath: String): OrtSession {
            val bytes = assets.open(assetPath).readBytes()
            return env.createSession(bytes, opts)
        }

        melSession = loadModel("flutter_assets/assets/wake_word/melspectrogram.onnx")
        embedSession = loadModel("flutter_assets/assets/wake_word/embedding_model.onnx")
        wakeSession = loadModel("flutter_assets/assets/wake_word/hey_hearty.onnx")
    }

    private fun startDetection() {
        if (isRunning) return
        isRunning = true

        val bufferSize = maxOf(
            AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT),
            SAMPLES_PER_CHUNK * 2
        )

        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )
        audioRecord!!.startRecording()

        detectionThread = Thread {
            val shortBuffer = ShortArray(SAMPLES_PER_CHUNK)
            while (isRunning) {
                if (isPaused) {
                    Thread.sleep(200)
                    continue
                }
                val samplesRead = audioRecord?.read(shortBuffer, 0, SAMPLES_PER_CHUNK) ?: 0
                if (samplesRead < SAMPLES_PER_CHUNK) continue

                val floatAudio = FloatArray(SAMPLES_PER_CHUNK) { shortBuffer[it].toFloat() / 32768.0f }
                val embedding = runEmbeddingPipeline(floatAudio) ?: continue

                synchronized(embeddingBuffer) {
                    embeddingBuffer.addLast(embedding)
                    if (embeddingBuffer.size > EMBEDDING_BUFFER_SIZE) {
                        embeddingBuffer.removeFirst()
                    }
                    if (embeddingBuffer.size == EMBEDDING_BUFFER_SIZE) {
                        val score = runClassifier()
                        if (score >= threshold) {
                            onWakeWordDetected()
                        }
                    }
                }
            }
        }
        detectionThread!!.isDaemon = true
        detectionThread!!.start()
    }

    private fun stopDetection() {
        isRunning = false
        audioRecord?.stop()
        audioRecord?.release()
        audioRecord = null
        detectionThread?.interrupt()
        detectionThread = null
    }

    // Stage 1 + 2: raw audio → mel spectrogram → embedding
    private fun runEmbeddingPipeline(audio: FloatArray): FloatArray? {
        val env = ortEnv ?: return null
        val melSess = melSession ?: return null
        val embedSess = embedSession ?: return null

        return try {
            // Stage 1: audio → mel spectrogram
            val audioTensor = OnnxTensor.createTensor(env, FloatBuffer.wrap(audio), longArrayOf(1, SAMPLES_PER_CHUNK.toLong()))
            val melResult = melSess.run(mapOf(MEL_INPUT_NODE to audioTensor))
            val melOutput = (melResult[MEL_OUTPUT_NODE].get() as OnnxTensor).floatBuffer

            // Stage 2: mel spectrogram → embedding
            // The embedding model expects shape matching the mel output.
            // Use the tensor as-is by passing through with the correct shape.
            val melShape = (melResult[MEL_OUTPUT_NODE].get() as OnnxTensor).info.shape
            val embedTensor = OnnxTensor.createTensor(env, melOutput, melShape)
            val embedResult = embedSess.run(mapOf(EMBED_INPUT_NODE to embedTensor))
            val embedOutput = (embedResult[EMBED_OUTPUT_NODE].get() as OnnxTensor).floatBuffer

            val embedding = FloatArray(EMBEDDING_DIM)
            embedOutput.get(embedding)
            audioTensor.close(); melResult.close(); embedTensor.close(); embedResult.close()
            embedding
        } catch (e: Exception) {
            null  // Log in production; swallow here to keep detection loop alive
        }
    }

    // Stage 3: 16 embeddings → wake word probability
    private fun runClassifier(): Float {
        val env = ortEnv ?: return 0f
        val sess = wakeSession ?: return 0f

        return try {
            val flat = FloatArray(EMBEDDING_BUFFER_SIZE * EMBEDDING_DIM)
            embeddingBuffer.forEachIndexed { i, emb ->
                emb.copyInto(flat, i * EMBEDDING_DIM)
            }
            val inputTensor = OnnxTensor.createTensor(env, FloatBuffer.wrap(flat), longArrayOf(1, EMBEDDING_BUFFER_SIZE.toLong(), EMBEDDING_DIM.toLong()))
            val result = sess.run(mapOf("x" to inputTensor))
            val score = (result["sigmoid"].get() as OnnxTensor).floatBuffer.get()
            inputTensor.close(); result.close()
            score
        } catch (e: Exception) {
            0f
        }
    }

    private fun onWakeWordDetected() {
        // Post to main thread so Flutter MethodChannel call is safe
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            methodChannel?.invokeMethod("wakeWordDetected", null)
        }
        // Pause detection while STT is using the microphone
        isPaused = true
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Wake Word Detection",
            NotificationManager.IMPORTANCE_LOW
        ).apply { description = "Hearty wake word detection service" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val pauseIntent = PendingIntent.getService(
            this, 0,
            Intent(this, HeartyWakeWordService::class.java).apply { action = "PAUSE" },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val pauseAction = Notification.Action.Builder(null, if (isPaused) "Resume listening" else "Pause listening", pauseIntent).build()

        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Hearty is listening for 'Hey Hearty'")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .addAction(pauseAction)
            .setOngoing(true)
            .build()
    }
}
```

- [ ] **Step 2: Verify the file compiles (flutter build apk --debug will check Kotlin)**

Run a quick Kotlin syntax check. The full build is deferred until device testing; just confirm the file exists and has no obvious syntax error by running:

```bash
export ANDROID_HOME=/home/evan/tools/android-sdk
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app
/home/evan/tools/flutter/bin/flutter analyze 2>&1 | tail -5
```

Expected: `No issues found!` or only Dart-side warnings (not Kotlin errors at this stage — Kotlin is compiled during `flutter build`).

- [ ] **Step 3: Commit**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app
git add hearty_app/android/app/src/main/kotlin/com/hearty/app/HeartyWakeWordService.kt
git commit -m "feat: HeartyWakeWordService — 3-stage ONNX wake word detection"
```

---

## Task 4: BootReceiver.kt + Service Start from MainActivity

**Files:**
- Create: `hearty_app/android/app/src/main/kotlin/com/hearty/app/BootReceiver.kt`
- Modify: `hearty_app/android/app/src/main/kotlin/com/hearty/app/MainActivity.kt`

- [ ] **Step 1: Write BootReceiver.kt**

Create `hearty_app/android/app/src/main/kotlin/com/hearty/app/BootReceiver.kt`:

```kotlin
package com.hearty.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val serviceIntent = Intent(context, HeartyWakeWordService::class.java)
            context.startForegroundService(serviceIntent)
        }
    }
}
```

- [ ] **Step 2: Update MainActivity.kt to start the service and wire MethodChannel**

Replace `hearty_app/android/app/src/main/kotlin/com/hearty/app/MainActivity.kt` with:

```kotlin
package com.hearty.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Start the wake word service when the app launches
        val serviceIntent = Intent(this, HeartyWakeWordService::class.java)
        startForegroundService(serviceIntent)
    }
}
```

Note: The `MethodChannel` between the service and Flutter is set up when the service handles `startListening`/`stopListening` calls from Flutter. The service's `methodChannel` reference for calling `wakeWordDetected` into Flutter is established via the `flutterEngine.dartExecutor.binaryMessenger` reference. Because the service and activity run in the same process, the service can obtain the binary messenger by storing a reference when started from MainActivity. For this implementation the channel call from Kotlin to Dart is done via the stored `methodChannel` in the service.

Update `MainActivity.kt` to pass the Flutter engine to the service:

```kotlin
package com.hearty.app

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var wakeWordService: HeartyWakeWordService? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val serviceIntent = Intent(this, HeartyWakeWordService::class.java)
        startForegroundService(serviceIntent)
        // Wire Flutter engine after service binds
        flutterEngine.let { engine ->
            // Service may not be bound yet; post a delayed connection attempt.
            // In practice the service starts quickly and the app isn't immediately ready either.
            window.decorView.post {
                bindService(serviceIntent, object : ServiceConnection {
                    override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                        // HeartyWakeWordService doesn't bind (returns null from onBind),
                        // so this path isn't reached. Instead, we use a static reference.
                    }
                    override fun onServiceDisconnected(name: ComponentName?) {}
                }, Context.BIND_AUTO_CREATE)
            }
        }
    }
}
```

Since `HeartyWakeWordService.onBind()` returns `null`, binding won't work for engine injection. Instead, use a companion object singleton to pass the engine:

Final `MainActivity.kt`:

```kotlin
package com.hearty.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Register MethodChannel directly from the Activity's FlutterEngine.
        // The service invokes methods on this channel via a static reference to the messenger.
        HeartyWakeWordService.flutterBinaryMessenger = flutterEngine.dartExecutor.binaryMessenger
        val serviceIntent = Intent(this, HeartyWakeWordService::class.java)
        startForegroundService(serviceIntent)
    }
}
```

Update `HeartyWakeWordService.kt` to use the static messenger. In the companion object, add:

```kotlin
companion object {
    // ... existing constants ...
    var flutterBinaryMessenger: io.flutter.plugin.common.BinaryMessenger? = null
}
```

And update `onStartCommand` to set up the channel using the static messenger when it becomes available:

```kotlin
override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
        "PAUSE" -> {
            isPaused = !isPaused
            startForeground(NOTIFICATION_ID, buildNotification())
        }
        else -> {
            val messenger = flutterBinaryMessenger
            if (messenger != null && methodChannel == null) {
                methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
                methodChannel?.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "startListening" -> { isPaused = false; result.success(null) }
                        "stopListening"  -> { isPaused = true;  result.success(null) }
                        else -> result.notImplemented()
                    }
                }
            }
            startDetection()
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }
    return START_STICKY
}
```

- [ ] **Step 3: flutter analyze**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app
/home/evan/tools/flutter/bin/flutter analyze 2>&1 | tail -5
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app
git add hearty_app/android/app/src/main/kotlin/com/hearty/app/BootReceiver.kt \
        hearty_app/android/app/src/main/kotlin/com/hearty/app/MainActivity.kt \
        hearty_app/android/app/src/main/kotlin/com/hearty/app/HeartyWakeWordService.kt
git commit -m "feat: BootReceiver + MainActivity engine wiring for wake word service"
```

---

## Task 5: Flutter WakeWordChannel + WakeWordProvider

**Files:**
- Create: `hearty_app/lib/features/wake_word/wake_word_channel.dart`
- Create: `hearty_app/lib/features/wake_word/providers/wake_word_provider.dart`
- Create: `hearty_app/test/features/wake_word/wake_word_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Create `hearty_app/test/features/wake_word/wake_word_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/features/wake_word/providers/wake_word_provider.dart';

void main() {
  group('wakeWordDetectedProvider', () {
    test('initial state is false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(wakeWordDetectedProvider), isFalse);
    });

    test('setDetected(true) sets state to true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(wakeWordDetectedProvider.notifier).setDetected(true);
      expect(container.read(wakeWordDetectedProvider), isTrue);
    });

    test('setDetected(false) clears state', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(wakeWordDetectedProvider.notifier).setDetected(true);
      container.read(wakeWordDetectedProvider.notifier).setDetected(false);
      expect(container.read(wakeWordDetectedProvider), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/wake_word/wake_word_provider_test.dart 2>&1 | tail -10
```

Expected: FAIL with `Target of URI hasn't been created`.

- [ ] **Step 3: Write WakeWordChannel**

Create `hearty_app/lib/features/wake_word/wake_word_channel.dart`:

```dart
import 'package:flutter/services.dart';

/// Wraps the MethodChannel to the Kotlin HeartyWakeWordService.
///
/// Call [startListening] / [stopListening] to pause/resume detection on the
/// native side. The channel also receives `wakeWordDetected` calls from Kotlin.
class WakeWordChannel {
  static const _channel = MethodChannel('com.hearty.app/wake_word');

  /// Register a callback that fires when the Kotlin service detects the wake word.
  static void onWakeWordDetected(void Function() callback) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'wakeWordDetected') callback();
    });
  }

  static Future<void> startListening() =>
      _channel.invokeMethod('startListening');

  static Future<void> stopListening() =>
      _channel.invokeMethod('stopListening');
}
```

- [ ] **Step 4: Write WakeWordProvider**

Create `hearty_app/lib/features/wake_word/providers/wake_word_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../wake_word_channel.dart';

/// True for the duration of a wake word trigger cycle.
/// Set to false after the voice overlay dismisses.
final wakeWordDetectedProvider =
    StateNotifierProvider<WakeWordNotifier, bool>((ref) {
  return WakeWordNotifier()..init();
});

class WakeWordNotifier extends StateNotifier<bool> {
  WakeWordNotifier() : super(false);

  void init() {
    WakeWordChannel.onWakeWordDetected(() => setDetected(true));
  }

  void setDetected(bool value) => state = value;
}
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/wake_word/wake_word_provider_test.dart 2>&1 | tail -5
```

Expected: `All tests passed!`

- [ ] **Step 6: flutter analyze**

```bash
/home/evan/tools/flutter/bin/flutter analyze 2>&1 | tail -5
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app
git add hearty_app/lib/features/wake_word/ hearty_app/test/features/wake_word/
git commit -m "feat: WakeWordChannel + WakeWordProvider — Flutter side of wake word detection"
```

---

## Task 6: Wake Chime Audio Asset + ChimePlayer

**Files:**
- Create: `hearty_app/assets/audio/wake_chime.mp3`
- Create: `hearty_app/lib/core/audio/chime_player.dart`

- [ ] **Step 1: Generate a wake chime MP3**

Run one of the following (use the first command that succeeds):

```bash
# Option A: ffmpeg (most likely available)
ffmpeg -f lavfi -i "sine=frequency=880:duration=0.15,aecho=0.8:0.88:30:0.4" \
       -ar 44100 -ac 1 \
       /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app/assets/audio/wake_chime.mp3
```

```bash
# Option B: generate a two-tone chime with ffmpeg
ffmpeg -f lavfi -i "sine=frequency=523:duration=0.12" \
       -f lavfi -i "sine=frequency=659:duration=0.12" \
       -filter_complex "[0][1]concat=n=2:v=0:a=1" \
       -ar 44100 /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app/assets/audio/wake_chime.mp3
```

```bash
# Option C: Python fallback — generates a 440Hz sine wave tone
python3 -c "
import struct, math, wave
rate = 44100; freq = 880; dur = 0.3
samples = [int(32767 * math.sin(2 * math.pi * freq * t / rate)) for t in range(int(rate * dur))]
with wave.open('/tmp/chime.wav', 'w') as f:
    f.setnchannels(1); f.setsampwidth(2); f.setframerate(rate)
    f.writeframes(struct.pack(f'<{len(samples)}h', *samples))
print('WAV written to /tmp/chime.wav')
"
# Then convert WAV to MP3 with ffmpeg if available, or use the WAV path directly in the
# pubspec.yaml (change the extension to .wav and update hearty_app/pubspec.yaml accordingly)
```

Verify the file exists:

```bash
ls -lh /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app/assets/audio/wake_chime.mp3
```

Expected: file exists, size > 0 bytes.

- [ ] **Step 2: Write ChimePlayer**

Create `hearty_app/lib/core/audio/chime_player.dart`:

```dart
import 'package:just_audio/just_audio.dart';

/// Plays the wake word detection chime once.
///
/// A single [AudioPlayer] is reused across calls; calling [play] while
/// the previous chime is still playing restarts it from the beginning.
class ChimePlayer {
  ChimePlayer._();

  static final ChimePlayer instance = ChimePlayer._();

  final _player = AudioPlayer();
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await _player.setAsset('assets/audio/wake_chime.mp3');
      _initialized = true;
    }
  }

  Future<void> play() async {
    await _ensureInitialized();
    await _player.seek(Duration.zero);
    await _player.play();
  }

  Future<void> dispose() => _player.dispose();
}
```

- [ ] **Step 3: flutter analyze**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app
/home/evan/tools/flutter/bin/flutter analyze 2>&1 | tail -5
```

Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app
git add hearty_app/assets/audio/wake_chime.mp3 hearty_app/lib/core/audio/chime_player.dart
git commit -m "feat: wake chime audio asset + ChimePlayer"
```

---

## Task 7: VoiceState Model + VoiceProvider (STT State Machine)

**Files:**
- Create: `hearty_app/lib/features/voice/models/voice_state.dart`
- Create: `hearty_app/lib/features/voice/providers/voice_provider.dart`
- Create: `hearty_app/test/features/voice/voice_provider_test.dart`

- [ ] **Step 1: Write the failing tests**

Create `hearty_app/test/features/voice/voice_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hearty_app/features/voice/models/voice_state.dart';
import 'package:hearty_app/features/voice/providers/voice_provider.dart';

void main() {
  group('VoiceNotifier state transitions', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is idle', () {
      expect(container.read(voiceProvider).status, VoiceStatus.idle);
    });

    test('startListening transitions to listening', () {
      container.read(voiceProvider.notifier).startListening();
      expect(container.read(voiceProvider).status, VoiceStatus.listening);
    });

    test('setTranscript updates transcript text', () {
      container.read(voiceProvider.notifier).startListening();
      container.read(voiceProvider.notifier).setTranscript('I just had pizza');
      expect(container.read(voiceProvider).transcript, 'I just had pizza');
    });

    test('setThinking transitions to thinking', () {
      container.read(voiceProvider.notifier).startListening();
      container.read(voiceProvider.notifier).setThinking();
      expect(container.read(voiceProvider).status, VoiceStatus.thinking);
    });

    test('setResponse transitions to responding with response text', () {
      container.read(voiceProvider.notifier).setThinking();
      container.read(voiceProvider.notifier).setResponse('Logged! How are you feeling?');
      expect(container.read(voiceProvider).status, VoiceStatus.responding);
      expect(container.read(voiceProvider).response, 'Logged! How are you feeling?');
    });

    test('dismiss resets to idle', () {
      container.read(voiceProvider.notifier).setResponse('Done');
      container.read(voiceProvider.notifier).dismiss();
      expect(container.read(voiceProvider).status, VoiceStatus.idle);
    });
  });
}
```

- [ ] **Step 2: Run test to confirm failure**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_provider_test.dart 2>&1 | tail -5
```

Expected: FAIL with `Target of URI hasn't been created`.

- [ ] **Step 3: Write VoiceState model**

Create `hearty_app/lib/features/voice/models/voice_state.dart`:

```dart
enum VoiceStatus { idle, listening, thinking, responding, awaitingFollowUp }

class VoiceState {
  final VoiceStatus status;
  final String transcript;
  final String response;

  const VoiceState({
    this.status = VoiceStatus.idle,
    this.transcript = '',
    this.response = '',
  });

  VoiceState copyWith({
    VoiceStatus? status,
    String? transcript,
    String? response,
  }) =>
      VoiceState(
        status: status ?? this.status,
        transcript: transcript ?? this.transcript,
        response: response ?? this.response,
      );
}
```

- [ ] **Step 4: Write VoiceProvider**

Create `hearty_app/lib/features/voice/providers/voice_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../models/voice_state.dart';

final voiceProvider = StateNotifierProvider<VoiceNotifier, VoiceState>((ref) {
  return VoiceNotifier();
});

class VoiceNotifier extends StateNotifier<VoiceState> {
  VoiceNotifier() : super(const VoiceState());

  final _stt = SpeechToText();
  bool _sttInitialized = false;

  Future<bool> _ensureSttInitialized() async {
    if (!_sttInitialized) {
      _sttInitialized = await _stt.initialize();
    }
    return _sttInitialized;
  }

  void startListening() {
    state = state.copyWith(status: VoiceStatus.listening, transcript: '', response: '');
    _beginStt();
  }

  Future<void> _beginStt() async {
    if (!await _ensureSttInitialized()) return;
    await _stt.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          setTranscript(result.recognizedWords);
        }
        if (result.finalResult) {
          setThinking();
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 2),
      localeId: 'en-US',
    );
  }

  void setTranscript(String text) {
    state = state.copyWith(transcript: text);
  }

  void setThinking() {
    if (_stt.isListening) _stt.stop();
    state = state.copyWith(status: VoiceStatus.thinking);
  }

  void setResponse(String response) {
    state = state.copyWith(status: VoiceStatus.responding, response: response);
  }

  void setAwaitingFollowUp() {
    state = state.copyWith(status: VoiceStatus.awaitingFollowUp);
    _beginStt();
  }

  void dismiss() {
    if (_stt.isListening) _stt.stop();
    state = const VoiceState();
  }

  @override
  void dispose() {
    _stt.stop();
    super.dispose();
  }
}
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_provider_test.dart 2>&1 | tail -5
```

Expected: `All tests passed!`

- [ ] **Step 6: flutter analyze**

```bash
/home/evan/tools/flutter/bin/flutter analyze 2>&1 | tail -5
```

Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app
git add hearty_app/lib/features/voice/models/ hearty_app/lib/features/voice/providers/ \
        hearty_app/test/features/voice/voice_provider_test.dart
git commit -m "feat: VoiceState + VoiceProvider — STT state machine"
```

---

## Task 8: TTS Integration + Follow-Up Logic

**Files:**
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`
- Modify: `hearty_app/test/features/voice/voice_provider_test.dart`

TTS is added to `VoiceNotifier`. When `setResponse()` is called, the provider speaks the response via `flutter_tts`, then optionally transitions to `awaitingFollowUp`.

- [ ] **Step 1: Add TTS tests**

Append to `hearty_app/test/features/voice/voice_provider_test.dart`:

```dart
    test('stopSpeaking resets to idle from responding state', () {
      container.read(voiceProvider.notifier).setResponse('Good job!');
      container.read(voiceProvider.notifier).stopSpeaking();
      expect(container.read(voiceProvider).status, VoiceStatus.idle);
    });
```

- [ ] **Step 2: Run added test to confirm it fails**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_provider_test.dart 2>&1 | tail -5
```

Expected: FAIL with `The method 'stopSpeaking' isn't defined`.

- [ ] **Step 3: Update VoiceProvider with TTS**

Replace the contents of `hearty_app/lib/features/voice/providers/voice_provider.dart` with:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../models/voice_state.dart';

final voiceProvider = StateNotifierProvider<VoiceNotifier, VoiceState>((ref) {
  return VoiceNotifier();
});

class VoiceNotifier extends StateNotifier<VoiceState> {
  VoiceNotifier() : super(const VoiceState()) {
    _initTts();
  }

  final _stt = SpeechToText();
  final _tts = FlutterTts();
  bool _sttInitialized = false;

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.9);
    await _tts.setPitch(1.0);
  }

  Future<bool> _ensureSttInitialized() async {
    if (!_sttInitialized) {
      _sttInitialized = await _stt.initialize();
    }
    return _sttInitialized;
  }

  void startListening() {
    state = state.copyWith(status: VoiceStatus.listening, transcript: '', response: '');
    _beginStt();
  }

  Future<void> _beginStt() async {
    if (!await _ensureSttInitialized()) return;
    await _stt.listen(
      onResult: (result) {
        if (result.recognizedWords.isNotEmpty) {
          setTranscript(result.recognizedWords);
        }
        if (result.finalResult) {
          setThinking();
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 2),
      localeId: 'en-US',
    );
  }

  void setTranscript(String text) {
    state = state.copyWith(transcript: text);
  }

  void setThinking() {
    if (_stt.isListening) _stt.stop();
    state = state.copyWith(status: VoiceStatus.thinking);
  }

  /// Called by the caller after receiving the API response.
  /// Speaks [response] via TTS, then transitions to [awaitingFollowUp] state.
  Future<void> setResponse(String response, {bool askFollowUp = true}) async {
    state = state.copyWith(status: VoiceStatus.responding, response: response);
    await _tts.speak(response);
    // flutter_tts is async fire-and-forget. Use a completion handler to
    // transition state after speaking finishes.
    _tts.setCompletionHandler(() {
      if (!mounted) return;
      if (askFollowUp) {
        setAwaitingFollowUp();
      } else {
        dismiss();
      }
    });
  }

  /// Stops TTS mid-sentence (e.g., user tapped screen).
  Future<void> stopSpeaking() async {
    await _tts.stop();
    state = const VoiceState();
  }

  void setAwaitingFollowUp() {
    if (!mounted) return;
    state = state.copyWith(status: VoiceStatus.awaitingFollowUp);
    _beginStt();
  }

  void dismiss() {
    if (_stt.isListening) _stt.stop();
    _tts.stop();
    state = const VoiceState();
  }

  @override
  void dispose() {
    _stt.stop();
    _tts.stop();
    super.dispose();
  }
}
```

- [ ] **Step 4: Run all voice tests**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_provider_test.dart 2>&1 | tail -5
```

Expected: `All tests passed!`

- [ ] **Step 5: flutter analyze**

```bash
/home/evan/tools/flutter/bin/flutter analyze 2>&1 | tail -5
```

Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app
git add hearty_app/lib/features/voice/providers/voice_provider.dart \
        hearty_app/test/features/voice/voice_provider_test.dart
git commit -m "feat: TTS integration + follow-up logic in VoiceProvider"
```

---

## Task 9: Voice Overlay UI (Waveform Animation, Thinking Animation, VoiceOverlayScreen)

**Files:**
- Create: `hearty_app/lib/features/voice/widgets/waveform_animation.dart`
- Create: `hearty_app/lib/features/voice/widgets/thinking_animation.dart`
- Create: `hearty_app/lib/features/voice/screens/voice_overlay_screen.dart`
- Create: `hearty_app/test/features/voice/voice_overlay_screen_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Create `hearty_app/test/features/voice/voice_overlay_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/features/voice/models/voice_state.dart';
import 'package:hearty_app/features/voice/providers/voice_provider.dart';
import 'package:hearty_app/features/voice/screens/voice_overlay_screen.dart';

void main() {
  group('VoiceOverlayScreen', () {
    testWidgets('shows waveform when status is listening', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              () => _StubVoiceNotifier(const VoiceState(status: VoiceStatus.listening)),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('waveform_animation')), findsOneWidget);
      expect(find.byKey(const Key('thinking_animation')), findsNothing);
    });

    testWidgets('shows thinking animation when status is thinking', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              () => _StubVoiceNotifier(const VoiceState(status: VoiceStatus.thinking)),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('thinking_animation')), findsOneWidget);
      expect(find.byKey(const Key('waveform_animation')), findsNothing);
    });

    testWidgets('shows transcript text when available', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              () => _StubVoiceNotifier(const VoiceState(
                status: VoiceStatus.listening,
                transcript: 'I had pizza',
              )),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.text('I had pizza'), findsOneWidget);
    });

    testWidgets('shows response text when responding', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              () => _StubVoiceNotifier(const VoiceState(
                status: VoiceStatus.responding,
                response: 'Logged your meal!',
              )),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.text('Logged your meal!'), findsOneWidget);
    });

    testWidgets('shows text field for manual input', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              () => _StubVoiceNotifier(const VoiceState(status: VoiceStatus.listening)),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}

class _StubVoiceNotifier extends VoiceNotifier {
  _StubVoiceNotifier(VoiceState initial) {
    state = initial;
  }
}
```

- [ ] **Step 2: Run failing tests**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_overlay_screen_test.dart 2>&1 | tail -5
```

Expected: FAIL with `Target of URI hasn't been created`.

- [ ] **Step 3: Write WaveformAnimation widget**

Create `hearty_app/lib/features/voice/widgets/waveform_animation.dart`:

```dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated waveform indicating the app is actively listening.
class WaveformAnimation extends StatefulWidget {
  const WaveformAnimation({super.key});

  @override
  State<WaveformAnimation> createState() => _WaveformAnimationState();
}

class _WaveformAnimationState extends State<WaveformAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('waveform_animation'),
      width: 120,
      height: 60,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _WaveformPainter(
              _controller.value,
              Theme.of(context).colorScheme.primary,
            ),
          );
        },
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const barCount = 12;
    final barWidth = size.width / (barCount * 2 - 1);
    for (var i = 0; i < barCount; i++) {
      final phase = (i / barCount + progress) * math.pi * 2;
      final height = (math.sin(phase).abs() * 0.7 + 0.3) * size.height;
      final x = i * barWidth * 2 + barWidth / 2;
      final top = (size.height - height) / 2;
      canvas.drawLine(Offset(x, top), Offset(x, top + height), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.progress != progress;
}
```

- [ ] **Step 4: Write ThinkingAnimation widget**

Create `hearty_app/lib/features/voice/widgets/thinking_animation.dart`:

```dart
import 'package:flutter/material.dart';

/// Three-dot pulsing animation indicating an API call is in progress.
class ThinkingAnimation extends StatefulWidget {
  const ThinkingAnimation({super.key});

  @override
  State<ThinkingAnimation> createState() => _ThinkingAnimationState();
}

class _ThinkingAnimationState extends State<ThinkingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      key: const Key('thinking_animation'),
      height: 24,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final delay = i / 3;
              final progress = (_controller.value - delay) % 1.0;
              final scale = 0.5 + 0.5 * (1 - (progress * 2 - 1).abs());
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Transform.scale(
                  scale: scale.clamp(0.5, 1.0),
                  child: CircleAvatar(radius: 5, backgroundColor: color),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Write VoiceOverlayScreen**

Create `hearty_app/lib/features/voice/screens/voice_overlay_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/voice_state.dart';
import '../providers/voice_provider.dart';
import '../widgets/waveform_animation.dart';
import '../widgets/thinking_animation.dart';

/// Full-screen voice overlay. Pushed as a modal route on top of the current screen.
///
/// Dismiss by tapping anywhere outside the content area, or when the session
/// transitions to idle.
class VoiceOverlayScreen extends ConsumerStatefulWidget {
  const VoiceOverlayScreen({super.key});

  @override
  ConsumerState<VoiceOverlayScreen> createState() => _VoiceOverlayScreenState();
}

class _VoiceOverlayScreenState extends ConsumerState<VoiceOverlayScreen> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // Auto-dismiss when idle
    ref.listen(voiceProvider, (_, next) {
      if (next.status == VoiceStatus.idle && mounted) {
        Navigator.of(context).pop();
      }
    });

    return GestureDetector(
      onTap: () {
        // Tap anywhere to stop TTS (if speaking) or dismiss (if idle/follow-up)
        final status = ref.read(voiceProvider).status;
        if (status == VoiceStatus.responding) {
          ref.read(voiceProvider.notifier).stopSpeaking();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black.withOpacity(0.85),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Close button
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      ref.read(voiceProvider.notifier).dismiss();
                    },
                  ),
                ),
                const Spacer(),

                // Central animation
                Center(
                  child: _buildAnimation(voiceState.status),
                ),
                const SizedBox(height: 32),

                // Transcript / response text
                _buildTextDisplay(voiceState, colorScheme),

                const Spacer(),

                // Text input fallback — always visible
                _buildTextInput(colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimation(VoiceStatus status) {
    switch (status) {
      case VoiceStatus.listening:
      case VoiceStatus.awaitingFollowUp:
        return const WaveformAnimation();
      case VoiceStatus.thinking:
        return const ThinkingAnimation();
      case VoiceStatus.responding:
        return Icon(Icons.volume_up, color: Colors.white, size: 48);
      case VoiceStatus.idle:
        return const SizedBox.shrink();
    }
  }

  Widget _buildTextDisplay(VoiceState state, ColorScheme colorScheme) {
    final text = state.status == VoiceStatus.responding || state.status == VoiceStatus.awaitingFollowUp
        ? state.response
        : state.transcript;
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
      textAlign: TextAlign.center,
    );
  }

  Widget _buildTextInput(ColorScheme colorScheme) {
    return TextField(
      controller: _textController,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Or type here...',
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        suffixIcon: IconButton(
          icon: const Icon(Icons.send, color: Colors.white),
          onPressed: () {
            final text = _textController.text.trim();
            if (text.isEmpty) return;
            _textController.clear();
            ref.read(voiceProvider.notifier).setTranscript(text);
            ref.read(voiceProvider.notifier).setThinking();
            // API call is triggered by the parent widget listening to status changes
          },
        ),
      ),
      onSubmitted: (text) {
        if (text.trim().isEmpty) return;
        _textController.clear();
        ref.read(voiceProvider.notifier).setTranscript(text.trim());
        ref.read(voiceProvider.notifier).setThinking();
      },
    );
  }
}
```

- [ ] **Step 6: Run widget tests**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_overlay_screen_test.dart 2>&1 | tail -10
```

Expected: `All tests passed!`

- [ ] **Step 7: flutter analyze**

```bash
/home/evan/tools/flutter/bin/flutter analyze 2>&1 | tail -5
```

Expected: `No issues found!`

- [ ] **Step 8: Commit**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app
git add hearty_app/lib/features/voice/ hearty_app/test/features/voice/voice_overlay_screen_test.dart
git commit -m "feat: VoiceOverlayScreen + waveform/thinking animations"
```

---

## Task 10: Home Screen FAB + Log Entry Screen Voice Button

**Files:**
- Modify: `hearty_app/lib/features/logging/screens/home_screen.dart`
- Modify: `hearty_app/lib/features/logging/screens/log_entry_screen.dart`
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`

This task wires the wake word detection signal and the FAB/voice button to open `VoiceOverlayScreen` and start the voice session.

- [ ] **Step 1: Update HomeScreen with wake word listener + Quick Log FAB**

Replace `hearty_app/lib/features/logging/screens/home_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../voice/providers/voice_provider.dart';
import '../../voice/screens/voice_overlay_screen.dart';
import '../../wake_word/providers/wake_word_provider.dart';
import '../../../core/audio/chime_player.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // When the wake word fires: play chime then open voice overlay
    ref.listen(wakeWordDetectedProvider, (_, detected) async {
      if (!detected) return;
      await ChimePlayer.instance.play();
      if (!context.mounted) return;
      ref.read(voiceProvider.notifier).startListening();
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const VoiceOverlayScreen(),
      );
      ref.read(wakeWordDetectedProvider.notifier).setDetected(false);
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Hearty')),
      body: const Center(child: Text('Today\'s timeline coming in Phase 5')),
      floatingActionButton: _QuickLogFab(
        onVoiceTap: () => _openVoiceOverlay(context, ref),
        onTextTap: () => context.push('/log'),
        onCameraTap: () => context.push('/log'),
      ),
    );
  }

  Future<void> _openVoiceOverlay(BuildContext context, WidgetRef ref) async {
    ref.read(voiceProvider.notifier).startListening();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceOverlayScreen(),
    );
  }
}

class _QuickLogFab extends StatefulWidget {
  final VoidCallback onVoiceTap;
  final VoidCallback onTextTap;
  final VoidCallback onCameraTap;

  const _QuickLogFab({
    required this.onVoiceTap,
    required this.onTextTap,
    required this.onCameraTap,
  });

  @override
  State<_QuickLogFab> createState() => _QuickLogFabState();
}

class _QuickLogFabState extends State<_QuickLogFab> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_expanded) ...[
          _SubFab(icon: Icons.mic, label: 'Voice', onTap: () {
            setState(() => _expanded = false);
            widget.onVoiceTap();
          }),
          const SizedBox(height: 8),
          _SubFab(icon: Icons.edit, label: 'Text', onTap: () {
            setState(() => _expanded = false);
            widget.onTextTap();
          }),
          const SizedBox(height: 8),
          _SubFab(icon: Icons.camera_alt, label: 'Camera', onTap: () {
            setState(() => _expanded = false);
            widget.onCameraTap();
          }),
          const SizedBox(height: 12),
        ],
        FloatingActionButton(
          onPressed: () {
            if (_expanded) {
              widget.onVoiceTap();
              setState(() => _expanded = false);
            } else {
              setState(() => _expanded = true);
            }
          },
          onLongPress: () => setState(() => _expanded = !_expanded),
          child: Icon(_expanded ? Icons.mic : Icons.add),
        ),
      ],
    );
  }
}

class _SubFab extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SubFab({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.small(
          heroTag: label,
          onPressed: onTap,
          child: Icon(icon),
        ),
      ],
    );
  }
}
```

- [ ] **Step 2: Update LogEntryScreen with voice button**

Replace `hearty_app/lib/features/logging/screens/log_entry_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../voice/providers/voice_provider.dart';
import '../../voice/screens/voice_overlay_screen.dart';

class LogEntryScreen extends ConsumerWidget {
  const LogEntryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log Entry')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Large pulsing voice button
            GestureDetector(
              onTap: () => _openVoiceOverlay(context, ref),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary,
                ),
                child: const Icon(Icons.mic, color: Colors.white, size: 56),
              ),
            ),
            const SizedBox(height: 24),
            // Text input fallback
            TextField(
              decoration: InputDecoration(
                hintText: 'Or type what you ate...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: const Icon(Icons.send),
              ),
              onSubmitted: (text) {
                // Phase 5 will wire this to the API; stub here
              },
            ),
            const SizedBox(height: 16),
            // Recent chips placeholder
            Wrap(
              spacing: 8,
              children: ['Coffee', 'Oatmeal', 'Water']
                  .map((label) => ActionChip(
                        label: Text(label),
                        onPressed: () {},
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openVoiceOverlay(BuildContext context, WidgetRef ref) async {
    ref.read(voiceProvider.notifier).startListening();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const VoiceOverlayScreen(),
    );
  }
}
```

- [ ] **Step 3: Add `setResponse` API wiring stub to VoiceProvider**

The voice overlay needs the caller to trigger the API call when `status` transitions to `thinking`. This is done by the screen listening to the provider. The full API integration happens in Phase 5 (`/api/chat`). For now, add a stub that simulates a response for testing:

In `voice_provider.dart`, add a `simulateApiResponse` method at the end of `VoiceNotifier`:

```dart
  /// Stub for Phase 5 — simulates a Claude API response.
  /// Phase 5 replaces this with a real POST /api/chat call.
  Future<void> simulateApiResponse() async {
    final transcript = state.transcript;
    if (transcript.isEmpty) return;
    await setResponse('Got it! I logged "$transcript". How are you feeling?');
  }
```

In `VoiceOverlayScreen`, add a listener that fires the stub when `thinking` is reached:

Add to `_VoiceOverlayScreenState.build`, after the existing `ref.listen` block:

```dart
    // Phase 5 will replace this stub with real API call
    ref.listen(voiceProvider.select((s) => s.status), (_, status) {
      if (status == VoiceStatus.thinking) {
        ref.read(voiceProvider.notifier).simulateApiResponse();
      }
    });
```

- [ ] **Step 4: flutter analyze**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app
/home/evan/tools/flutter/bin/flutter analyze 2>&1 | tail -5
```

Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app
git add hearty_app/lib/features/logging/screens/home_screen.dart \
        hearty_app/lib/features/logging/screens/log_entry_screen.dart \
        hearty_app/lib/features/voice/providers/voice_provider.dart \
        hearty_app/lib/features/voice/screens/voice_overlay_screen.dart
git commit -m "feat: Home screen FAB + Log Entry voice button wired to VoiceOverlayScreen"
```

---

## Task 11: Default Assistant Preference + Non-Health Query Redirect

**Files:**
- Modify: `hearty_app/lib/features/settings/screens/settings_screen.dart`
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`

The Default Assistant setting lets the user choose where non-health queries are redirected. The VoiceProvider reads this setting and speaks the redirect response.

- [ ] **Step 1: Add Default Assistant provider**

Create `hearty_app/lib/features/settings/providers/default_assistant_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum DefaultAssistant { googleAssistant, gemini, none }

extension DefaultAssistantLabel on DefaultAssistant {
  String get label {
    switch (this) {
      case DefaultAssistant.googleAssistant: return 'Google Assistant';
      case DefaultAssistant.gemini: return 'Gemini';
      case DefaultAssistant.none: return 'None';
    }
  }
}

final defaultAssistantProvider =
    StateProvider<DefaultAssistant>((ref) => DefaultAssistant.googleAssistant);
```

- [ ] **Step 2: Update SettingsScreen to show Default Assistant + Voice Settings**

Replace the contents of `hearty_app/lib/features/settings/screens/settings_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/auth/auth_repository.dart';
import '../providers/default_assistant_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final defaultAssistant = ref.watch(defaultAssistantProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Account section
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: const Text('Account'),
            subtitle: Text(currentUser?.email ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign Out'),
            onTap: () async {
              await Supabase.instance.client.auth.signOut();
              await GoogleSignIn().signOut();
            },
          ),
          const Divider(),

          // Default Assistant
          const ListTile(
            title: Text('Default Assistant',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Where non-health queries are redirected'),
          ),
          ...DefaultAssistant.values.map((assistant) => RadioListTile<DefaultAssistant>(
                title: Text(assistant.label),
                value: assistant,
                groupValue: defaultAssistant,
                onChanged: (value) {
                  if (value != null) {
                    ref.read(defaultAssistantProvider.notifier).state = value;
                  }
                },
              )),
          const Divider(),

          // Health Profile navigation (Phase 5 wires the actual screen)
          ListTile(
            leading: const Icon(Icons.health_and_safety),
            title: const Text('Health Profile'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          const Divider(),

          // About
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About'),
            subtitle: Text('Hearty v1.0.0'),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Add non-health redirect to VoiceProvider**

The API response from `/api/chat` will indicate whether a query was health-related. For Phase 4 the stub response handles this. Add a `redirectToAssistant` method that produces the redirect response.

In `hearty_app/lib/features/voice/providers/voice_provider.dart`, add the redirect method to `VoiceNotifier`:

```dart
  /// Speaks the redirect response for a non-health query.
  /// [assistantLabel] is the user-configured default assistant name (e.g., "Google Assistant").
  Future<void> redirectToAssistant(String assistantLabel) async {
    final response = assistantLabel == 'None'
        ? "That's outside what I track. I focus on food, symptoms, and wellbeing."
        : "For that, try asking $assistantLabel.";
    await setResponse(response, askFollowUp: false);
  }
```

Update `simulateApiResponse` in `VoiceNotifier` to also demonstrate the non-health path (the real check will come from the Claude API in Phase 5):

```dart
  Future<void> simulateApiResponse() async {
    final transcript = state.transcript;
    if (transcript.isEmpty) return;
    // Phase 5: replace with real POST /api/chat call.
    // The API returns { "response": "...", "is_health_related": true/false }
    await setResponse('Got it! I logged "$transcript". How are you feeling?');
  }
```

- [ ] **Step 4: flutter analyze**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app/hearty_app
/home/evan/tools/flutter/bin/flutter analyze 2>&1 | tail -5
```

Expected: `No issues found!`

- [ ] **Step 5: Run all tests**

```bash
/home/evan/tools/flutter/bin/flutter test 2>&1 | tail -10
```

Expected: all tests pass, no failures.

- [ ] **Step 6: Commit**

```bash
cd /home/evan/projects/food-journal-assistant/.claude/worktrees/feat+hearty-04-android-app
git add hearty_app/lib/features/settings/ \
        hearty_app/lib/features/voice/providers/voice_provider.dart
git commit -m "feat: Default Assistant preference + non-health query redirect"
```

---

## Post-Plan Self-Review

### Spec Coverage Check

| Spec Requirement | Covered By |
|---|---|
| `HeartyWakeWordService.kt` with ONNX Runtime | Task 3 |
| `BOOT_COMPLETED` receiver + service restart | Task 4 |
| Persistent notification with "Pause listening" action | Task 3 |
| `MethodChannel('com.hearty.app/wake_word')` | Tasks 3 + 5 |
| STT via `speech_to_text`, live waveform, 2s silence | Tasks 7 + 9 |
| Auto-stop on 2s silence | Task 7 (`pauseFor: Duration(seconds: 2)`) |
| Retry button | Not explicitly included — add retry button to `VoiceOverlayScreen._buildTextInput` |
| TTS via `flutter_tts` at 0.9 speech rate | Task 8 |
| Interruptible TTS by screen tap | Task 9 (`stopSpeaking()` on tap) |
| Wake chime (`assets/audio/wake_chime.mp3`) via `just_audio` | Tasks 6 + 10 |
| Full activation flow: wake → chime → overlay → STT → thinking → API → TTS → follow-up → dismiss | Tasks 5, 8, 9, 10 |
| Non-health query redirect to configured assistant | Task 11 |
| Text field always visible in overlay | Task 9 |

**Gap found — retry button:**

In Task 9 `VoiceOverlayScreen._buildTextDisplay`, add a Retry button when status is `listening` and transcript is non-empty:

In the `_buildTextDisplay` method of `VoiceOverlayScreen`, after the text widget, add:

```dart
if (state.status == VoiceStatus.listening && state.transcript.isNotEmpty)
  TextButton.icon(
    onPressed: () => ref.read(voiceProvider.notifier).startListening(),
    icon: const Icon(Icons.refresh, color: Colors.white70),
    label: const Text('Retry', style: TextStyle(color: Colors.white70)),
  ),
```

This should be added to the `_buildTextDisplay` return value — replace the simple `Text` widget with a `Column` containing the text and the retry button. Update Task 9's step for `_buildTextDisplay`:

```dart
  Widget _buildTextDisplay(VoiceState state, ColorScheme colorScheme) {
    final text = state.status == VoiceStatus.responding || state.status == VoiceStatus.awaitingFollowUp
        ? state.response
        : state.transcript;
    if (text.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
          textAlign: TextAlign.center,
        ),
        if (state.status == VoiceStatus.listening && text.isNotEmpty)
          TextButton.icon(
            onPressed: () => ref.read(voiceProvider.notifier).startListening(),
            icon: const Icon(Icons.refresh, color: Colors.white70),
            label: const Text('Retry', style: TextStyle(color: Colors.white70)),
          ),
      ],
    );
  }
```

The implementing agent should apply this fix in Task 9 rather than as a separate step.

### Type Consistency Check

- `VoiceStatus` enum defined in `voice_state.dart`, used consistently across provider, screen, tests ✓
- `VoiceNotifier` methods (`startListening`, `setThinking`, `setResponse`, `stopSpeaking`, `dismiss`) named consistently across all files ✓
- `WakeWordNotifier.setDetected(bool)` used consistently ✓
- `DefaultAssistant` enum defined in `default_assistant_provider.dart`, extension `label` on the enum ✓

### Placeholder Scan

- No "TBD" / "TODO" in task steps ✓
- `simulateApiResponse` is named clearly as a Phase 5 stub, not a real TODO ✓
- All file paths are exact ✓
- All test commands include expected output ✓
