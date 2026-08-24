package com.rohanchari.steptracker

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.work.CoroutineWorker
import androidx.work.ListenableWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.HttpURLConnection
import java.net.URL
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Native Health Connect intake. Race/box work is owned by the backend queue. */
class StepSyncWorker(
    context: Context,
    params: androidx.work.WorkerParameters,
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val prefs = applicationContext.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        val client = try {
            HealthConnectClient.getOrCreate(applicationContext)
        } catch (_: Exception) {
            Log.i(TAG, "Health Connect unavailable; skipping background sync")
            return Result.success()
        }
        return runStepSyncWorker(
            state = AndroidStepSyncState(prefs),
            health = AndroidStepSyncHealth(client),
            transport = AndroidStepSyncTransport(),
            appVersion = try {
                applicationContext.packageManager
                    .getPackageInfo(applicationContext.packageName, 0)
                    .versionName
            } catch (_: Exception) {
                null
            },
        )
    }

    companion object {
        private const val TAG = "StepSyncWorker"
        private const val PREFS_FILE = "FlutterSharedPreferences"
        private const val PERIODIC_NAME = "step_sync_periodic"
        private const val EXPEDITED_NAME = "step_sync_expedited"

        fun schedulePeriodic(context: Context) {
            val request = PeriodicWorkRequestBuilder<StepSyncWorker>(Duration.ofMinutes(15)).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                PERIODIC_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }

        fun enqueueExpedited(context: Context) {
            val request = OneTimeWorkRequestBuilder<StepSyncWorker>()
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                EXPEDITED_NAME,
                ExistingWorkPolicy.REPLACE,
                request,
            )
        }
    }
}

internal fun workerResultFor(outcome: StepSyncRunOutcome): ListenableWorker.Result =
    when (outcome) {
        StepSyncRunOutcome.SUCCESS -> ListenableWorker.Result.success()
        StepSyncRunOutcome.RETRY -> ListenableWorker.Result.retry()
    }

internal suspend fun runStepSyncWorker(
    state: StepSyncState,
    health: StepSyncHealth,
    transport: StepSyncTransport,
    now: () -> Instant = Instant::now,
    zone: () -> ZoneId = ZoneId::systemDefault,
    appVersion: String? = null,
): ListenableWorker.Result = try {
    workerResultFor(
        StepSyncEngine(
            state = state,
            health = health,
            transport = transport,
            now = now,
            zone = zone,
            appVersion = appVersion,
        ).run()
    )
} catch (_: Exception) {
    ListenableWorker.Result.retry()
}

private class AndroidStepSyncState(private val prefs: SharedPreferences) : StepSyncState {
    override fun readSession() = StepSyncSession(
        sessionToken = prefs.getString("flutter.auth_session_token", null),
        ownerId = prefs.getString("flutter.auth_backend_user_id", null),
        backendBaseUrl = prefs.getString("flutter.background_sync_backend_base_url", null),
        healthAuthorized = prefs.getBoolean("flutter.health_authorized", false),
    )

    override fun readPendingV2(): String? = prefs.getString(PENDING_V2, null)
    override fun writePendingV2(value: String?): Boolean = write(PENDING_V2, value)
    override fun readPendingLegacy(): String? = prefs.getString(PENDING_LEGACY, null)
    override fun writePendingLegacy(value: String?): Boolean = write(PENDING_LEGACY, value)
    override fun readNegativeCapability(): String? = prefs.getString(NEGATIVE_CAPABILITY, null)
    override fun writeNegativeCapability(value: String?): Boolean = write(NEGATIVE_CAPABILITY, value)

    private fun write(key: String, value: String?): Boolean =
        prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.commit()

    companion object {
        private const val PENDING_V2 = "flutter.android_background_sync_v2_pending"
        private const val PENDING_LEGACY = "flutter.android_background_sync_legacy_pending"
        private const val NEGATIVE_CAPABILITY = "flutter.android_background_sync_negative_capability"
    }
}

internal interface AndroidStepSyncHealthGateway {
    suspend fun hasStepReadPermission(): Boolean
    suspend fun accurateSteps(start: Instant, end: Instant): Int
}

private class HealthConnectStepSyncGateway(
    private val client: HealthConnectClient,
) : AndroidStepSyncHealthGateway {
    override suspend fun hasStepReadPermission(): Boolean =
        client.permissionController.getGrantedPermissions().contains(
            HealthPermission.getReadPermission(StepsRecord::class)
        )

    override suspend fun accurateSteps(start: Instant, end: Instant): Int {
        val aggregate = client.aggregate(
            AggregateRequest(
                metrics = setOf(StepsRecord.COUNT_TOTAL),
                timeRangeFilter = TimeRangeFilter.between(start, end),
            )
        )
        val deduped = aggregate[StepsRecord.COUNT_TOTAL] ?: 0L
        val manual = try {
            client.readRecords(
                ReadRecordsRequest(
                    recordType = StepsRecord::class,
                    timeRangeFilter = TimeRangeFilter.between(start, end),
                )
            ).records
                .filter { it.metadata.recordingMethod == RECORDING_METHOD_MANUALLY_ENTERED }
                .sumOf { it.count }
        } catch (_: Exception) {
            0L
        }
        return (deduped - manual).coerceAtLeast(0L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
    }

    companion object {
        private const val RECORDING_METHOD_MANUALLY_ENTERED = 3
    }
}

internal class AndroidStepSyncHealth(
    private val gateway: AndroidStepSyncHealthGateway,
) : StepSyncHealth {
    constructor(client: HealthConnectClient) : this(HealthConnectStepSyncGateway(client))

    override suspend fun readSnapshot(now: Instant, zone: ZoneId): StepSyncSnapshot? {
        if (!gateway.hasStepReadPermission()) return null
        val localNow = now.atZone(zone)
        val startOfDay = localNow.toLocalDate().atStartOfDay(zone).toInstant()
        val daily = try {
            gateway.accurateSteps(startOfDay, now)
        } catch (error: Exception) {
            // Permission can be revoked after the persisted Flutter preference
            // was written. That is a terminal no-op, while a still-authorized
            // provider/read failure must be retried by WorkManager.
            if (!gateway.hasStepReadPermission()) return null
            throw error
        }
        if (daily <= 0) return null

        val samples = mutableListOf<StepSyncSample>()
        try {
            StepSyncEngine.completedHourRanges(now, zone).forEach { (bucketStart, bucketEnd) ->
                val steps = gateway.accurateSteps(bucketStart, bucketEnd)
                if (steps > 0) {
                    samples += StepSyncSample(
                        periodStart = ISO.format(bucketStart),
                        periodEnd = ISO.format(bucketEnd),
                        steps = steps,
                    )
                }
            }
        } catch (_: Exception) {
            // Preserve the daily intake when an optional hourly read fails.
        }
        return StepSyncSnapshot(
            date = localNow.toLocalDate().toString(),
            steps = daily,
            samples = samples,
            timeZone = zone.id,
        )
    }

    companion object {
        private val ISO = DateTimeFormatter.ISO_INSTANT
    }
}

private class AndroidStepSyncTransport : StepSyncTransport {
    override suspend fun post(request: StepSyncHttpRequest): StepSyncHttpResponse =
        withContext(Dispatchers.IO) {
            var connection: HttpURLConnection? = null
            try {
                connection = URL(request.url).openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                request.headers.forEach { (key, value) ->
                    connection.setRequestProperty(key, value)
                }
                connection.connectTimeout = 15_000
                connection.readTimeout = 15_000
                connection.doOutput = true
                connection.outputStream.use { it.write(request.body.toByteArray(Charsets.UTF_8)) }
                val status = connection.responseCode
                val stream = if (status >= 400) connection.errorStream else connection.inputStream
                val body = try {
                    stream?.bufferedReader()?.use { it.readText() }
                } catch (_: Exception) {
                    null
                }
                StepSyncHttpResponse(status, body)
            } catch (_: Exception) {
                StepSyncHttpResponse.networkFailure()
            } finally {
                connection?.disconnect()
            }
        }
}
