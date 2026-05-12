package com.hearty.app

import android.content.Context
import android.util.Log
import androidx.work.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

private const val TAG = "AnalysisWorker"
private const val WORK_NAME_PERIODIC = "hearty_analysis_nightly"
private const val WORK_NAME_IDLE = "hearty_analysis_idle"

/**
 * Background worker that calls the Hearty signal analysis endpoint.
 *
 * Pre-checks /api/trends/analyze/status before running analysis to skip
 * unnecessary work when no new data exists.
 */
class AnalysisWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val baseUrl = inputData.getString(KEY_BASE_URL) ?: DEFAULT_BASE_URL
            val token = inputData.getString(KEY_AUTH_TOKEN)

            // Check status first — skip if no new data
            val status = fetchJson("$baseUrl/api/trends/analyze/status", token)
            val hasNewData = status?.optBoolean("has_new_data", false) ?: false
            if (!hasNewData) {
                Log.d(TAG, "No new data since last analysis — skipping")
                return@withContext Result.success()
            }

            // Run analysis
            postJson("$baseUrl/api/trends/analyze", token)
            Log.d(TAG, "Analysis completed successfully")
            Result.success()
        } catch (e: Exception) {
            Log.w(TAG, "Analysis failed: ${e.message}")
            // Retry up to 3 times on transient errors
            if (runAttemptCount < 3) Result.retry() else Result.failure()
        }
    }

    private fun fetchJson(urlString: String, token: String?): JSONObject? {
        val connection = URL(urlString).openConnection() as HttpURLConnection
        connection.requestMethod = "GET"
        connection.connectTimeout = 10_000
        connection.readTimeout = 15_000
        if (token != null) connection.setRequestProperty("Authorization", "Bearer $token")
        return try {
            val body = connection.inputStream.bufferedReader().readText()
            JSONObject(body)
        } finally {
            connection.disconnect()
        }
    }

    private fun postJson(urlString: String, token: String?) {
        val connection = URL(urlString).openConnection() as HttpURLConnection
        connection.requestMethod = "POST"
        connection.connectTimeout = 10_000
        connection.readTimeout = 60_000  // analysis can take a while
        connection.setRequestProperty("Content-Type", "application/json")
        if (token != null) connection.setRequestProperty("Authorization", "Bearer $token")
        connection.doOutput = true
        connection.outputStream.write("{}".toByteArray())
        val code = connection.responseCode
        connection.disconnect()
        if (code !in 200..299) throw RuntimeException("HTTP $code from analyze endpoint")
    }

    companion object {
        const val KEY_BASE_URL = "base_url"
        const val KEY_AUTH_TOKEN = "auth_token"
        const val DEFAULT_BASE_URL = "http://10.0.2.2:8000"

        /**
         * Enqueue a nightly periodic job (once per day, network required).
         * Call once on app start; WorkManager deduplicates via KEEP policy.
         */
        fun enqueuePeriodic(context: Context, baseUrl: String, authToken: String?) {
            val data = workDataOf(
                KEY_BASE_URL to baseUrl,
                KEY_AUTH_TOKEN to authToken,
            )
            val request = PeriodicWorkRequestBuilder<AnalysisWorker>(24, TimeUnit.HOURS)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .build()
                )
                .setInputData(data)
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME_PERIODIC,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }

        /**
         * Enqueue a one-time idle run after a meal or wellbeing log.
         * Requires network + device idle. KEEP policy prevents duplicate queuing.
         */
        fun enqueueIdle(context: Context, baseUrl: String, authToken: String?) {
            val data = workDataOf(
                KEY_BASE_URL to baseUrl,
                KEY_AUTH_TOKEN to authToken,
            )
            val request = OneTimeWorkRequestBuilder<AnalysisWorker>()
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.CONNECTED)
                        .setRequiresDeviceIdle(true)
                        .build()
                )
                .setInputData(data)
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME_IDLE,
                ExistingWorkPolicy.KEEP,
                request,
            )
        }
    }
}
