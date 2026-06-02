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
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.nio.FloatBuffer
import java.util.LinkedList

class HeartyWakeWordService : Service() {

    companion object {
        const val CHANNEL_ID = "hearty_wake_word"
        // Separate high-priority channel for the wake-word trigger notification.
        // Unlike CHANNEL_ID (which silences the ongoing service notification),
        // this channel uses the default alert sound so Android won't demote
        // the fullScreenIntent to a regular heads-up on some devices.
        const val TRIGGER_CHANNEL_ID = "hearty_wake_trigger"
        const val NOTIFICATION_ID = 1001
        const val METHOD_CHANNEL = "com.hearty.app/wake_word"

        const val SAMPLE_RATE = 16000
        // 80ms chunks match the openWakeWord Python pipeline (1280 samples → ~5 mel frames).
        // Using overlapping mel frame windows dramatically improves detection vs. the old
        // 12640-sample non-overlapping approach where the classifier saw mostly background embeddings.
        const val SAMPLES_PER_CHUNK = 1280

        const val MEL_INPUT_NODE = "input"
        const val MEL_OUTPUT_NODE = "output"
        const val EMBED_INPUT_NODE = "input_1"
        const val EMBED_OUTPUT_NODE = "conv2d_19"

        const val MEL_BINS = 32
        const val MEL_WINDOW_FRAMES = 76   // frames the embedding model expects
        const val EMBEDDING_BUFFER_SIZE = 16
        const val EMBEDDING_DIM = 96
        // hey_hearty (custom-trained, 50 k samples) scores in the 0.05–0.20 range on the
        // wake phrase vs. >0.5 for the pre-trained hey_jarvis model. Lower threshold
        // accordingly; 2-consecutive debounce prevents single-chunk noise from firing.
        const val DEFAULT_THRESHOLD = 0.05f
        const val DEBOUNCE_HITS = 2
        const val TAG = "HeartyWakeWord"

        // The openWakeWord Python streaming pipeline prepends 3 STFT hops (3×160 = 480 samples)
        // of prior audio to each chunk so mel windows span chunk boundaries correctly.
        const val MEL_CONTEXT_SAMPLES = 480

        var flutterBinaryMessenger: BinaryMessenger? = null
    }

    private var wakeLock: PowerManager.WakeLock? = null
    private var audioRecord: AudioRecord? = null
    private var ortEnv: OrtEnvironment? = null
    private var melSession: OrtSession? = null
    private var embedSession: OrtSession? = null
    private var wakeSession: OrtSession? = null
    private var detectionThread: Thread? = null
    private var isRunning = false
    private var isPaused = false
    private var threshold = DEFAULT_THRESHOLD

    // Sliding mel frame buffer — grows up to MEL_WINDOW_FRAMES, then rolls.
    private val melFrameBuffer = LinkedList<FloatArray>()
    private val embeddingBuffer = LinkedList<FloatArray>()
    // Rolling context: last 480 samples of the previous chunk, prepended to every mel call.
    private var rawAudioContext = FloatArray(MEL_CONTEXT_SAMPLES)
    private var methodChannel: MethodChannel? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        initOnnxModels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (checkSelfPermission(android.Manifest.permission.RECORD_AUDIO)
                != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            stopSelf()
            return START_NOT_STICKY
        }
        when (intent?.action) {
            "PAUSE" -> {
                isPaused = !isPaused
                startForeground(NOTIFICATION_ID, buildNotification())
            }
            else -> {
                val messenger = flutterBinaryMessenger
                if (messenger != null) {
                    methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
                    methodChannel?.setMethodCallHandler { call, result ->
                        when (call.method) {
                            "startListening" -> {
                                isPaused = false
                                // Re-acquire the mic after STT finishes
                                try { audioRecord?.startRecording() } catch (_: Exception) {}
                                result.success(null)
                            }
                            "stopListening" -> {
                                isPaused = true
                                // Actually release the mic so SpeechRecognizer can acquire it
                                audioRecord?.stop()
                                result.success(null)
                            }
                            else -> result.notImplemented()
                        }
                    }
                }
                startForeground(NOTIFICATION_ID, buildNotification())
                startDetection()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopDetection()
        melSession?.close(); embedSession?.close(); wakeSession?.close()
        ortEnv?.close()
        super.onDestroy()
    }

    private fun initOnnxModels() {
        try {
            ortEnv = OrtEnvironment.getEnvironment()
            val env = ortEnv!!
            OrtSession.SessionOptions().use { opts ->
                fun loadModel(assetPath: String): OrtSession {
                    Log.d(TAG, "Loading model: $assetPath")
                    return env.createSession(assets.open(assetPath).readBytes(), opts)
                }
                melSession   = loadModel("flutter_assets/assets/wake_word/melspectrogram.onnx")
                embedSession = loadModel("flutter_assets/assets/wake_word/embedding_model.onnx")
                wakeSession  = loadModel("flutter_assets/assets/wake_word/hey_hearty.onnx")
            }
            Log.d(TAG, "All ONNX models loaded successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load ONNX models: ${e.message}", e)
        }
    }

    private fun startDetection() {
        if (isRunning) return
        isRunning = true

        val bufferSize = maxOf(
            AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT),
            SAMPLES_PER_CHUNK * 4
        )
        audioRecord = AudioRecord(
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            bufferSize
        )
        if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
            audioRecord?.release(); audioRecord = null
            isRunning = false
            @Suppress("DEPRECATION")
            stopForeground(true)
            stopSelf()
            return
        }
        audioRecord!!.startRecording()

        // Keep the CPU alive when the screen is off so the detection thread keeps running.
        // PARTIAL_WAKE_LOCK allows the display to sleep while preventing CPU deep-sleep.
        wakeLock = getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "hearty:WakeWordDetection")
            .also { it.acquire() }

        Log.d(TAG, "AudioRecord started — sliding window detection loop beginning")

        detectionThread = Thread {
            val shortBuffer = ShortArray(SAMPLES_PER_CHUNK)
            var chunkCount = 0
            var maxScore = 0f
            var consecutiveHits = 0

            while (isRunning) {
                if (isPaused) { Thread.sleep(50); continue }
                val read = audioRecord?.read(shortBuffer, 0, SAMPLES_PER_CHUNK) ?: 0
                if (read < SAMPLES_PER_CHUNK) continue

                // openWakeWord expects raw int16 magnitudes as float32 — no normalization.
                val floatAudio = FloatArray(SAMPLES_PER_CHUNK) { shortBuffer[it].toFloat() }
                val rms = Math.sqrt(floatAudio.map { (it / 32768.0) * (it / 32768.0) }.average()).toFloat()

                // Prepend 480 samples of prior audio so the STFT windows span chunk boundaries
                // correctly — mirrors the Python streaming pipeline's raw_data_buffer slicing.
                val melInput = FloatArray(MEL_CONTEXT_SAMPLES + SAMPLES_PER_CHUNK)
                rawAudioContext.copyInto(melInput, 0)
                floatAudio.copyInto(melInput, MEL_CONTEXT_SAMPLES)
                floatAudio.copyInto(rawAudioContext, 0, SAMPLES_PER_CHUNK - MEL_CONTEXT_SAMPLES, SAMPLES_PER_CHUNK)

                // Stage 1: context+chunk → mel frames, then apply spec/10+2 transform.
                val newFrames = getMelFrames(melInput) ?: continue

                // Add new mel frames to the rolling 76-frame buffer.
                for (frame in newFrames) {
                    melFrameBuffer.addLast(frame)
                }
                while (melFrameBuffer.size > MEL_WINDOW_FRAMES) melFrameBuffer.removeFirst()

                // Only compute embeddings once the mel buffer is primed.
                if (melFrameBuffer.size < MEL_WINDOW_FRAMES) continue

                // Stage 2: 76 mel frames → 96-dim embedding.
                val embedding = computeEmbedding() ?: continue

                embeddingBuffer.addLast(embedding)
                if (embeddingBuffer.size > EMBEDDING_BUFFER_SIZE) embeddingBuffer.removeFirst()

                if (embeddingBuffer.size == EMBEDDING_BUFFER_SIZE) {
                    val score = runClassifier()
                    if (score > maxScore) maxScore = score
                    chunkCount++
                    // Heartbeat every ~4s; also log whenever there's meaningful audio or score.
                    if (chunkCount % 50 == 0 || score > 0.005f || rms > 0.005f) {
                        Log.d(TAG, "chunk=$chunkCount rms=${"%.4f".format(rms)} score=${"%.4f".format(score)} max=${"%.4f".format(maxScore)} hits=$consecutiveHits")
                    }
                    if (score >= threshold) {
                        consecutiveHits++
                        if (consecutiveHits >= DEBOUNCE_HITS) {
                            consecutiveHits = 0
                            Log.d(TAG, "WAKE WORD DETECTED! score=$score")
                            onWakeWordDetected()
                        }
                    } else {
                        consecutiveHits = 0
                    }
                }
            }
            Log.d(TAG, "Detection loop exited")
        }.also { it.isDaemon = true; it.start() }
    }

    private fun stopDetection() {
        isRunning = false
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
        audioRecord?.stop(); audioRecord?.release(); audioRecord = null
        detectionThread?.interrupt(); detectionThread = null
        melFrameBuffer.clear()
        embeddingBuffer.clear()
        rawAudioContext = FloatArray(MEL_CONTEXT_SAMPLES)
    }

    // Returns each mel frame as a FloatArray of MEL_BINS floats.
    private fun getMelFrames(audio: FloatArray): List<FloatArray>? {
        val env = ortEnv ?: return null
        return try {
            OnnxTensor.createTensor(env, FloatBuffer.wrap(audio), longArrayOf(1, audio.size.toLong())).use { audioTensor ->
                melSession!!.run(mapOf(MEL_INPUT_NODE to audioTensor)).use { result ->
                    val tensor = result[MEL_OUTPUT_NODE].get() as OnnxTensor
                    val allFloats = FloatArray(tensor.floatBuffer.remaining())
                    tensor.floatBuffer.get(allFloats)
                    // openWakeWord Python reference applies spec/10+2 after the mel model
                    // to align the output range with what the Google TF embedding model expects.
                    for (i in allFloats.indices) allFloats[i] = allFloats[i] / 10.0f + 2.0f
                    val nFrames = allFloats.size / MEL_BINS
                    List(nFrames) { i -> allFloats.copyOfRange(i * MEL_BINS, (i + 1) * MEL_BINS) }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Mel error: ${e.message}", e)
            null
        }
    }

    // Assembles the current 76-frame mel buffer into [1, 76, 32, 1] and runs the embedding model.
    private fun computeEmbedding(): FloatArray? {
        val env = ortEnv ?: return null
        return try {
            val melFlat = FloatArray(MEL_WINDOW_FRAMES * MEL_BINS)
            melFrameBuffer.forEachIndexed { i, frame -> frame.copyInto(melFlat, i * MEL_BINS) }
            OnnxTensor.createTensor(env, FloatBuffer.wrap(melFlat),
                longArrayOf(1, MEL_WINDOW_FRAMES.toLong(), MEL_BINS.toLong(), 1)).use { embedTensor ->
                embedSession!!.run(mapOf(EMBED_INPUT_NODE to embedTensor)).use { result ->
                    val embedding = FloatArray(EMBEDDING_DIM)
                    (result[EMBED_OUTPUT_NODE].get() as OnnxTensor).floatBuffer.get(embedding)
                    embedding
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Embedding error: ${e.message}", e)
            null
        }
    }

    // 16 embeddings [1, 16, 96] → sigmoid score.
    private fun runClassifier(): Float {
        val env = ortEnv ?: return 0f
        return try {
            val flat = FloatArray(EMBEDDING_BUFFER_SIZE * EMBEDDING_DIM)
            embeddingBuffer.forEachIndexed { i, emb -> emb.copyInto(flat, i * EMBEDDING_DIM) }
            OnnxTensor.createTensor(env, FloatBuffer.wrap(flat),
                longArrayOf(1, EMBEDDING_BUFFER_SIZE.toLong(), EMBEDDING_DIM.toLong())).use { inputTensor ->
                wakeSession!!.run(mapOf("x" to inputTensor)).use { result ->
                    (result["sigmoid"].get() as OnnxTensor).floatBuffer.get()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Classifier error: ${e.message}", e)
            0f
        }
    }

    private fun onWakeWordDetected() {
        isPaused = true
        audioRecord?.stop()
        melFrameBuffer.clear()
        embeddingBuffer.clear()

        val launchIntent = Intent(this@HeartyWakeWordService, MainActivity::class.java).apply {
            action = MainActivity.ACTION_WAKE_WORD_DETECTED
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
        }

        // If the user has granted "Display over other apps", we can call startActivity()
        // directly from the service — this bypasses Android 10+ background-start
        // restrictions and reliably brings the app to the foreground without any
        // user interaction. MainActivity.onNewIntent() then fires methodChannel
        // .invokeMethod("wakeWordDetected") which opens the Flutter voice overlay.
        if (Settings.canDrawOverlays(this)) {
            Handler(Looper.getMainLooper()).post {
                startActivity(launchIntent)
            }
            return
        }

        // Fallback: fire a fullScreenIntent notification. On Android 12+ this typically
        // shows as a heads-up ("Tap to speak") rather than launching the activity
        // directly, but it's the best we can do without overlay permission.
        val pendingIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val triggerNotification = Notification.Builder(this, TRIGGER_CHANNEL_ID)
            .setContentTitle("Hey Hearty")
            .setContentText("Tap to start speaking")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setCategory(Notification.CATEGORY_CALL)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(pendingIntent, true)
            .setAutoCancel(true)
            .build()
        getSystemService(NotificationManager::class.java)
            .notify(NOTIFICATION_ID + 1, triggerNotification)
    }

    private fun createNotificationChannel() {
        val nm = getSystemService(NotificationManager::class.java)
        // Silent ongoing service notification — no sound or vibration so it doesn't
        // alert the user every time the foreground service rebuilds its notification.
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Wake Word Detection", NotificationManager.IMPORTANCE_HIGH)
                .apply {
                    description = "Hearty wake word detection service"
                    setSound(null, null)
                    enableVibration(false)
                }
        )
        // Separate alert channel for the wake-word trigger — uses default sound so
        // Android treats fullScreenIntent as high-urgency and wakes the screen.
        nm.createNotificationChannel(
            NotificationChannel(TRIGGER_CHANNEL_ID, "Hey Hearty", NotificationManager.IMPORTANCE_HIGH)
                .apply {
                    description = "Alert when the wake word is detected"
                }
        )
    }

    private fun buildNotification(): Notification {
        val pauseIntent = PendingIntent.getService(
            this, 0,
            Intent(this, HeartyWakeWordService::class.java).apply { action = "PAUSE" },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val label = if (isPaused) "Resume listening" else "Pause listening"
        val action = Notification.Action.Builder(null, label, pauseIntent).build()
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Hearty is listening for 'Hey Hearty'")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .addAction(action)
            .setOngoing(true)
            .setGroup("hearty_wake_word_group")
            .build()
    }
}
