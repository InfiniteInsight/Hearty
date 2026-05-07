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
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.nio.FloatBuffer
import java.util.LinkedList

class HeartyWakeWordService : Service() {

    companion object {
        const val CHANNEL_ID = "hearty_wake_word"
        const val NOTIFICATION_ID = 1001
        const val METHOD_CHANNEL = "com.hearty.app/wake_word"

        const val SAMPLE_RATE = 16000
        const val SAMPLES_PER_CHUNK = 12640  // 790ms → exactly 76 mel frames

        // Model node names (verified by Python inspection)
        const val MEL_INPUT_NODE = "input"
        const val MEL_OUTPUT_NODE = "output"
        const val EMBED_INPUT_NODE = "input_1"
        const val EMBED_OUTPUT_NODE = "conv2d_19"

        const val EMBEDDING_BUFFER_SIZE = 16
        const val EMBEDDING_DIM = 96
        const val DEFAULT_THRESHOLD = 0.5f

        var flutterBinaryMessenger: BinaryMessenger? = null
    }

    private var audioRecord: AudioRecord? = null
    private var ortEnv: OrtEnvironment? = null
    private var melSession: OrtSession? = null
    private var embedSession: OrtSession? = null
    private var wakeSession: OrtSession? = null
    private var detectionThread: Thread? = null
    private var isRunning = false
    private var isPaused = false
    private var threshold = DEFAULT_THRESHOLD
    private val embeddingBuffer = LinkedList<FloatArray>()
    private var methodChannel: MethodChannel? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        initOnnxModels()
    }

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

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopDetection()
        ortEnv?.close()
        super.onDestroy()
    }

    private fun initOnnxModels() {
        ortEnv = OrtEnvironment.getEnvironment()
        val env = ortEnv!!
        val opts = OrtSession.SessionOptions()

        fun loadModel(assetPath: String): OrtSession =
            env.createSession(assets.open(assetPath).readBytes(), opts)

        melSession   = loadModel("flutter_assets/assets/wake_word/melspectrogram.onnx")
        embedSession = loadModel("flutter_assets/assets/wake_word/embedding_model.onnx")
        wakeSession  = loadModel("flutter_assets/assets/wake_word/hey_hearty.onnx")
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
                if (isPaused) { Thread.sleep(200); continue }
                val read = audioRecord?.read(shortBuffer, 0, SAMPLES_PER_CHUNK) ?: 0
                if (read < SAMPLES_PER_CHUNK) continue

                val floatAudio = FloatArray(SAMPLES_PER_CHUNK) { shortBuffer[it].toFloat() / 32768.0f }
                val embedding = runEmbeddingPipeline(floatAudio) ?: continue

                synchronized(embeddingBuffer) {
                    embeddingBuffer.addLast(embedding)
                    if (embeddingBuffer.size > EMBEDDING_BUFFER_SIZE) embeddingBuffer.removeFirst()
                    if (embeddingBuffer.size == EMBEDDING_BUFFER_SIZE) {
                        val score = runClassifier()
                        if (score >= threshold) onWakeWordDetected()
                    }
                }
            }
        }.also { it.isDaemon = true; it.start() }
    }

    private fun stopDetection() {
        isRunning = false
        audioRecord?.stop(); audioRecord?.release(); audioRecord = null
        detectionThread?.interrupt(); detectionThread = null
    }

    // Stage 1+2: raw float audio [12640] → mel [1,1,76,32] → reshape [1,76,32,1] → embed [1,1,1,96] → [96]
    private fun runEmbeddingPipeline(audio: FloatArray): FloatArray? {
        val env = ortEnv ?: return null
        return try {
            // Stage 1: audio → mel spectrogram [1, 1, 76, 32]
            val audioTensor = OnnxTensor.createTensor(env, FloatBuffer.wrap(audio), longArrayOf(1, SAMPLES_PER_CHUNK.toLong()))
            val melResult = melSession!!.run(mapOf(MEL_INPUT_NODE to audioTensor))
            val melTensor = melResult[MEL_OUTPUT_NODE].get() as OnnxTensor

            // mel shape is [1, 1, 76, 32]; flatten to FloatArray and reinterpret as [1, 76, 32, 1]
            val melFloats = FloatArray(76 * 32)
            melTensor.floatBuffer.get(melFloats)

            // Reshape [76, 32] → [1, 76, 32, 1]: the values are the same, just different logical shape
            val embedTensor = OnnxTensor.createTensor(env, FloatBuffer.wrap(melFloats), longArrayOf(1, 76, 32, 1))

            // Stage 2: embed [1, 76, 32, 1] → [1, 1, 1, 96]
            val embedResult = embedSession!!.run(mapOf(EMBED_INPUT_NODE to embedTensor))
            val embedTensorOut = embedResult[EMBED_OUTPUT_NODE].get() as OnnxTensor
            val embedding = FloatArray(EMBEDDING_DIM)
            embedTensorOut.floatBuffer.get(embedding)

            audioTensor.close(); melResult.close(); embedTensor.close(); embedResult.close()
            embedding
        } catch (e: Exception) {
            null
        }
    }

    // Stage 3: 16 embeddings [1, 16, 96] → sigmoid score
    private fun runClassifier(): Float {
        val env = ortEnv ?: return 0f
        return try {
            val flat = FloatArray(EMBEDDING_BUFFER_SIZE * EMBEDDING_DIM)
            embeddingBuffer.forEachIndexed { i, emb -> emb.copyInto(flat, i * EMBEDDING_DIM) }
            val inputTensor = OnnxTensor.createTensor(env, FloatBuffer.wrap(flat), longArrayOf(1, EMBEDDING_BUFFER_SIZE.toLong(), EMBEDDING_DIM.toLong()))
            val result = wakeSession!!.run(mapOf("x" to inputTensor))
            val score = (result["sigmoid"].get() as OnnxTensor).floatBuffer.get()
            inputTensor.close(); result.close()
            score
        } catch (e: Exception) { 0f }
    }

    private fun onWakeWordDetected() {
        isPaused = true  // pause mic while STT is active
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            methodChannel?.invokeMethod("wakeWordDetected", null)
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(CHANNEL_ID, "Wake Word Detection", NotificationManager.IMPORTANCE_LOW)
            .apply { description = "Hearty wake word detection service" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
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
            .build()
    }
}
