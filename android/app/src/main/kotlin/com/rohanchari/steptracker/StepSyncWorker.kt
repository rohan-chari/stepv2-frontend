package com.rohanchari.steptracker

import android.content.Context
import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Phase 2 — Android background step sync. A periodic (and, in Phase 3, expedited)
 * worker that reads today's steps from Health Connect and POSTs them to the backend
 * while the app is backgrounded or closed. Native Kotlin (not a Flutter headless
 * isolate) because the `health` plugin only manages the background-read PERMISSION,
 * not the read itself, and background isolates can't reliably reach platform channels.
 *
 * Mirrors the foreground/iOS pipeline exactly so totals don't diverge:
 *   - deduped-minus-manual step accuracy (HealthService.accurateAndroidTotal),
 *   - POSTs the existing /steps and /steps/samples shapes (no new fields),
 *   - sends X-Timezone (parity with iOS Fix C2) and skipRaceResolution:true on the
 *     daily post (parity with iOS Fix C3 — defer resolution to samples + Phase 0 cron),
 *   - reads the "flutter."-prefixed SharedPreferences keys (the same prefix gotcha
 *     that broke iOS background sync in Phase 1 Fix C1),
 *   - NEVER persists a 0 on a failed Health Connect read (returns retry/skip instead).
 */
class StepSyncWorker(
    context: Context,
    params: androidx.work.WorkerParameters
) : CoroutineWorker(context, params) {

    private val tag = "StepSyncWorker"

    override suspend fun doWork(): Result {
        // Flutter's legacy shared_preferences plugin stores in "FlutterSharedPreferences"
        // and prefixes every key with "flutter." — read the prefixed keys or all reads
        // come back empty (the Phase 1 C1 lesson, now on Android).
        val prefs = applicationContext.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE
        )

        if (!prefs.getBoolean("flutter.health_authorized", false)) {
            Log.i(tag, "Health not authorized; skipping background sync")
            return Result.success()
        }
        val sessionToken = prefs.getString("flutter.auth_session_token", null)
        if (sessionToken.isNullOrBlank()) {
            Log.i(tag, "No session token; skipping background sync")
            return Result.success()
        }
        val baseUrl = prefs.getString("flutter.background_sync_backend_base_url", null)
        if (baseUrl.isNullOrBlank()) {
            Log.i(tag, "No backend base URL persisted; skipping background sync")
            return Result.success()
        }
        // IANA id (e.g. "America/Los_Angeles") — matches the Dart FlutterTimezone source.
        val timeZone = ZoneId.systemDefault().id

        val client = try {
            HealthConnectClient.getOrCreate(applicationContext)
        } catch (e: Exception) {
            Log.w(tag, "Health Connect unavailable; skipping", e)
            return Result.success()
        }

        val zone = ZoneId.systemDefault()
        val now = Instant.now()
        val startOfDay = now.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
        val today = now.atZone(zone).toLocalDate().toString() // YYYY-MM-DD

        // 1. Daily total (deduped-minus-manual). A failed read returns null -> we skip
        //    the post rather than recording a spurious 0.
        val dailySteps = readAccurateSteps(client, startOfDay, now)
        if (dailySteps == null) {
            Log.w(tag, "Daily step read failed; retrying later (no 0 persisted)")
            return Result.retry()
        }
        if (dailySteps <= 0) {
            Log.d(tag, "No steps today; nothing to sync")
            return Result.success()
        }

        // 2. Hourly samples for today (best-effort; failure here doesn't fail the sync).
        val samples = readHourlySamples(client, startOfDay, now, zone)

        return withContext(Dispatchers.IO) {
            // skipRaceResolution:true — the samples post (and the Phase 0 cron) resolve
            // race state; don't resolve on the coarser daily total.
            val dailyBody = JSONObject()
                .put("steps", dailySteps)
                .put("date", today)
                .put("skipRaceResolution", true)
            val dailyStatus = post("$baseUrl/steps", sessionToken, timeZone, dailyBody.toString())
            when {
                dailyStatus in 200..299 -> { /* fall through to samples */ }
                dailyStatus == 401 || dailyStatus == 403 -> {
                    Log.w(tag, "Auth rejected on daily post ($dailyStatus); not retrying")
                    return@withContext Result.success()
                }
                else -> {
                    Log.w(tag, "Daily post failed ($dailyStatus); retrying")
                    return@withContext Result.retry()
                }
            }

            if (samples.length() > 0) {
                val samplesBody = JSONObject().put("samples", samples)
                val sampleStatus =
                    post("$baseUrl/steps/samples", sessionToken, timeZone, samplesBody.toString())
                if (sampleStatus !in 200..299) {
                    // Daily already succeeded; don't fail/retry the whole sync over samples.
                    Log.w(tag, "Samples post failed ($sampleStatus); daily already synced")
                }
            }
            Log.d(tag, "Background sync complete: $dailySteps steps, ${samples.length()} samples")
            Result.success()
        }
    }

    /** Deduped total minus manual entries (parity with HealthService.accurateAndroidTotal). */
    private suspend fun readAccurateSteps(
        client: HealthConnectClient,
        start: Instant,
        end: Instant
    ): Int? {
        return try {
            val agg: AggregationResult = client.aggregate(
                AggregateRequest(
                    metrics = setOf(StepsRecord.COUNT_TOTAL),
                    timeRangeFilter = TimeRangeFilter.between(start, end)
                )
            )
            val deduped = agg[StepsRecord.COUNT_TOTAL] ?: 0L
            val manual = readManualSteps(client, start, end)
            (deduped - manual).coerceAtLeast(0L).toInt()
        } catch (e: Exception) {
            Log.e(tag, "Health Connect read failed", e)
            null
        }
    }

    private suspend fun readManualSteps(
        client: HealthConnectClient,
        start: Instant,
        end: Instant
    ): Long {
        return try {
            val response = client.readRecords(
                ReadRecordsRequest(
                    recordType = StepsRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(start, end)
                )
            )
            response.records
                .filter { it.metadata.recordingMethod == RECORDING_METHOD_MANUALLY_ENTERED }
                .sumOf { it.count }
        } catch (e: Exception) {
            Log.w(tag, "Manual-step read failed; treating manual as 0", e)
            0L
        }
    }

    /** Hourly buckets for today, non-zero only. Best-effort; never throws. */
    private suspend fun readHourlySamples(
        client: HealthConnectClient,
        startOfDay: Instant,
        now: Instant,
        zone: ZoneId
    ): JSONArray {
        val samples = JSONArray()
        var bucketStart = startOfDay
        try {
            while (bucketStart.isBefore(now)) {
                val candidateEnd = bucketStart.plus(Duration.ofHours(1))
                val bucketEnd = if (candidateEnd.isAfter(now)) now else candidateEnd
                val steps = readAccurateSteps(client, bucketStart, bucketEnd) ?: 0
                if (steps > 0) {
                    samples.put(
                        JSONObject()
                            .put("periodStart", ISO.format(bucketStart))
                            .put("periodEnd", ISO.format(bucketEnd))
                            .put("steps", steps)
                    )
                }
                bucketStart = bucketEnd
            }
        } catch (e: Exception) {
            Log.w(tag, "Hourly sample read failed; posting daily only", e)
        }
        return samples
    }

    private fun post(urlStr: String, token: String, timeZone: String, body: String): Int {
        return try {
            val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("Authorization", "Bearer $token")
                setRequestProperty("X-Timezone", timeZone)
                connectTimeout = 15_000
                readTimeout = 15_000
                doOutput = true
            }
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            conn.disconnect()
            code
        } catch (e: Exception) {
            Log.e(tag, "POST $urlStr threw", e)
            -1
        }
    }

    companion object {
        private const val PERIODIC_NAME = "step_sync_periodic"
        private const val EXPEDITED_NAME = "step_sync_expedited"
        private val ISO: DateTimeFormatter = DateTimeFormatter.ISO_INSTANT

        // Health Connect's documented recording-method value for manually-entered data
        // (Metadata.RECORDING_METHOD_MANUALLY_ENTERED). Referenced by its stable int
        // value because the named constant's location changed across connect-client
        // versions; matches RecordingMethod.manual in the Dart `health` package.
        private const val RECORDING_METHOD_MANUALLY_ENTERED = 3

        /** 15-min periodic (the WorkManager floor; realistically 30–60+ min under Doze). */
        fun schedulePeriodic(context: Context) {
            val request = PeriodicWorkRequestBuilder<StepSyncWorker>(
                Duration.ofMinutes(15)
            ).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                PERIODIC_NAME,
                ExistingPeriodicWorkPolicy.KEEP, // don't reset the schedule on every launch
                request
            )
        }

        /** On-demand sync (Phase 3: enqueued when the backend pushes STEP_SYNC_REQUEST). */
        fun enqueueExpedited(context: Context) {
            val request = OneTimeWorkRequestBuilder<StepSyncWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                EXPEDITED_NAME,
                ExistingWorkPolicy.REPLACE,
                request
            )
        }
    }
}
