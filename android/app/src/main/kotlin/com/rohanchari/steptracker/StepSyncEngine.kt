package com.rohanchari.steptracker

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.UUID

data class StepSyncSession(
    val sessionToken: String?,
    val ownerId: String?,
    val backendBaseUrl: String?,
    val healthAuthorized: Boolean,
)

data class StepSyncSample(
    val periodStart: String,
    val periodEnd: String,
    val steps: Int,
)

data class StepSyncSnapshot(
    val date: String,
    val steps: Int,
    val samples: List<StepSyncSample>,
    val timeZone: String,
)

data class StepSyncHttpRequest(
    val url: String,
    val headers: Map<String, String>,
    val body: String,
)

data class StepSyncHttpResponse(
    val statusCode: Int?,
    val body: String?,
    val networkError: Boolean = false,
) {
    companion object {
        fun networkFailure() = StepSyncHttpResponse(null, null, true)
    }
}

enum class StepSyncRunOutcome { SUCCESS, RETRY }

interface StepSyncState {
    fun readSession(): StepSyncSession
    fun readPendingV2(): String?
    fun writePendingV2(value: String?): Boolean
    fun readPendingLegacy(): String?
    fun writePendingLegacy(value: String?): Boolean
    fun readNegativeCapability(): String?
    fun writeNegativeCapability(value: String?): Boolean
}

interface StepSyncHealth {
    suspend fun readSnapshot(now: Instant, zone: ZoneId): StepSyncSnapshot?
}

interface StepSyncTransport {
    suspend fun post(request: StepSyncHttpRequest): StepSyncHttpResponse
}

class StepSyncEngine(
    private val state: StepSyncState,
    private val health: StepSyncHealth,
    private val transport: StepSyncTransport,
    private val now: () -> Instant = Instant::now,
    private val zone: () -> ZoneId = ZoneId::systemDefault,
    private val newIdempotencyKey: () -> String = { UUID.randomUUID().toString() },
    private val appVersion: String? = null,
    private val mutex: Mutex = sharedMutex,
) {
    suspend fun run(): StepSyncRunOutcome = mutex.withLock {
        val session = state.readSession()
        if (!session.healthAuthorized || session.sessionToken.isNullOrBlank() ||
            session.ownerId.isNullOrBlank() || session.backendBaseUrl.isNullOrBlank()
        ) {
            return@withLock StepSyncRunOutcome.SUCCESS
        }
        val valid = ValidSession(
            session.sessionToken,
            session.ownerId,
            session.backendBaseUrl.trimEnd('/'),
        )

        state.readPendingLegacy()?.let { raw ->
            val pending = decodeLegacy(raw)
            if (pending == null) {
                if (!sessionStillMatches(valid)) return@withLock StepSyncRunOutcome.SUCCESS
                if (state.readPendingLegacy() == raw && !state.writePendingLegacy(null)) {
                    return@withLock StepSyncRunOutcome.RETRY
                }
                if (!sessionStillMatches(valid)) return@withLock StepSyncRunOutcome.SUCCESS
            } else if (!pending.matches(valid)) {
                if (!clearOwnedLegacy(pending)) return@withLock StepSyncRunOutcome.RETRY
                if (!sessionStillMatches(valid)) return@withLock StepSyncRunOutcome.SUCCESS
            } else {
                val result = sendLegacy(pending, valid)
                if (result != StepSyncRunOutcome.SUCCESS) return@withLock result
                if (!sessionStillMatches(valid)) return@withLock StepSyncRunOutcome.SUCCESS
                return@withLock runFreshAfterCapabilityCheck(valid)
            }
        }

        state.readPendingV2()?.let { raw ->
            val pending = decodeV2(raw)
            if (pending == null) {
                if (!sessionStillMatches(valid)) return@withLock StepSyncRunOutcome.SUCCESS
                if (state.readPendingV2() == raw && !state.writePendingV2(null)) {
                    return@withLock StepSyncRunOutcome.RETRY
                }
                if (!sessionStillMatches(valid)) return@withLock StepSyncRunOutcome.SUCCESS
            } else if (!pending.matches(valid)) {
                if (!clearOwnedV2(pending)) return@withLock StepSyncRunOutcome.RETRY
                if (!sessionStillMatches(valid)) return@withLock StepSyncRunOutcome.SUCCESS
            } else {
                return@withLock sendV2(
                    pending,
                    valid,
                    recovery = true,
                    allowConflictRefresh = true,
                )
            }
        }

        runFreshAfterCapabilityCheck(valid)
    }

    private suspend fun runFreshAfterCapabilityCheck(session: ValidSession): StepSyncRunOutcome =
        when (negativeCapabilityState(session)) {
            CapabilityState.CURRENT -> runFresh(session, forceLegacy = true)
            CapabilityState.ABSENT -> runFresh(session, forceLegacy = false)
            CapabilityState.PERSISTENCE_FAILURE -> StepSyncRunOutcome.RETRY
            CapabilityState.SESSION_CHANGED -> StepSyncRunOutcome.SUCCESS
        }

    private suspend fun runFresh(
        session: ValidSession,
        forceLegacy: Boolean,
        allowConflictRefresh: Boolean = true,
    ): StepSyncRunOutcome {
        val instant = now()
        val snapshot = health.readSnapshot(instant, zone()) ?: return StepSyncRunOutcome.SUCCESS
        if (!sessionStillMatches(session)) return StepSyncRunOutcome.SUCCESS
        if (snapshot.steps <= 0) return StepSyncRunOutcome.SUCCESS
        val body = JSONObject()
            .put("date", snapshot.date)
            .put("steps", snapshot.steps)
            .put("samples", JSONArray().apply {
                snapshot.samples.forEach { sample ->
                    put(JSONObject()
                        .put("periodStart", sample.periodStart)
                        .put("periodEnd", sample.periodEnd)
                        .put("steps", sample.steps))
                }
            })
            .toString()

        if (forceLegacy) {
            val legacy = createLegacy(session, snapshot.timeZone, body)
                ?: return StepSyncRunOutcome.SUCCESS
            if (!sessionStillMatches(session)) return StepSyncRunOutcome.SUCCESS
            if (!state.writePendingLegacy(legacy.encode())) return StepSyncRunOutcome.RETRY
            return sendLegacy(legacy, session)
        }

        val envelope = V2Envelope(
            ownerId = session.ownerId,
            backendBaseUrl = session.backendBaseUrl,
            idempotencyKey = newIdempotencyKey(),
            timeZone = snapshot.timeZone,
            body = body,
            createdAtEpochMillis = instant.toEpochMilli(),
        )
        if (!sessionStillMatches(session)) return StepSyncRunOutcome.SUCCESS
        if (!state.writePendingV2(envelope.encode())) return StepSyncRunOutcome.RETRY
        return sendV2(envelope, session, recovery = false, allowConflictRefresh)
    }

    private suspend fun sendV2(
        envelope: V2Envelope,
        session: ValidSession,
        recovery: Boolean,
        allowConflictRefresh: Boolean,
    ): StepSyncRunOutcome {
        if (!sessionStillMatches(session)) {
            clearOwnedV2(envelope)
            return StepSyncRunOutcome.SUCCESS
        }
        val request = StepSyncHttpRequest(
            url = "${session.backendBaseUrl}/steps/sync-v2",
            headers = buildMap {
                put("Content-Type", "application/json")
                put("Authorization", "Bearer ${session.sessionToken}")
                put("Idempotency-Key", envelope.idempotencyKey)
                put("X-Timezone", envelope.timeZone)
                appVersion?.takeIf { it.isNotBlank() }?.let { put("X-App-Version", it) }
            },
            body = envelope.body,
        )
        var response = transport.post(request)
        if (!sessionStillMatches(session)) {
            clearOwnedV2(envelope)
            return StepSyncRunOutcome.SUCCESS
        }
        if (response.isRetryable() && !response.isAsyncDisabled()) {
            if (!sessionStillMatches(session)) {
                clearOwnedV2(envelope)
                return StepSyncRunOutcome.SUCCESS
            }
            response = transport.post(request)
            if (!sessionStillMatches(session)) {
                clearOwnedV2(envelope)
                return StepSyncRunOutcome.SUCCESS
            }
        }
        val status = response.statusCode
        if (!response.networkError && status == 202 && response.hasCapabilityMarker()) {
            if (!clearOwnedV2(envelope)) return StepSyncRunOutcome.RETRY
            if (!sessionStillMatches(session)) return StepSyncRunOutcome.SUCCESS
            if (!clearNegativeCapabilityIfOwned(session)) return StepSyncRunOutcome.RETRY
            return if (recovery && sessionStillMatches(session)) {
                runFresh(session, forceLegacy = false)
            } else StepSyncRunOutcome.SUCCESS
        }
        if (!response.networkError && status != null && status in 200..299) {
            return startLegacy(envelope, session)
        }
        if (!response.networkError && (status == 404 || response.isAsyncDisabled())) {
            return startLegacy(envelope, session)
        }
        if (!response.networkError && status == 409) {
            if (!clearOwnedV2(envelope)) return StepSyncRunOutcome.RETRY
            if (!sessionStillMatches(session)) return StepSyncRunOutcome.SUCCESS
            return if (allowConflictRefresh) {
                runFresh(session, forceLegacy = false, allowConflictRefresh = false)
            } else {
                StepSyncRunOutcome.SUCCESS
            }
        }
        if (!response.networkError && status in setOf(400, 401, 403, 413, 429)) {
            if (!clearOwnedV2(envelope)) return StepSyncRunOutcome.RETRY
            return StepSyncRunOutcome.SUCCESS
        }
        return StepSyncRunOutcome.RETRY
    }

    private suspend fun startLegacy(
        envelope: V2Envelope,
        session: ValidSession,
    ): StepSyncRunOutcome {
        if (!sessionStillMatches(session)) {
            clearOwnedV2(envelope)
            return StepSyncRunOutcome.SUCCESS
        }
        val legacy = createLegacy(session, envelope.timeZone, envelope.body)
            ?: return StepSyncRunOutcome.SUCCESS
        if (!sessionStillMatches(session)) {
            clearOwnedV2(envelope)
            return StepSyncRunOutcome.SUCCESS
        }
        if (!state.writePendingLegacy(legacy.encode())) return StepSyncRunOutcome.RETRY
        if (!sessionStillMatches(session)) {
            clearOwnedV2(envelope)
            clearOwnedLegacy(legacy)
            return StepSyncRunOutcome.SUCCESS
        }
        if (!cacheNegativeCapability(session)) return StepSyncRunOutcome.RETRY
        if (!clearOwnedV2(envelope)) return StepSyncRunOutcome.RETRY
        return sendLegacy(legacy, session)
    }

    private suspend fun sendLegacy(
        initial: LegacyEnvelope,
        session: ValidSession,
    ): StepSyncRunOutcome {
        var pending = initial
        if (!sessionStillMatches(session)) {
            clearOwnedLegacy(pending)
            return StepSyncRunOutcome.SUCCESS
        }
        if (!pending.dailyComplete) {
            if (!sessionStillMatches(session)) {
                clearOwnedLegacy(pending)
                return StepSyncRunOutcome.SUCCESS
            }
            val response = transport.post(legacyRequest(session, pending, "/steps", pending.dailyBody))
            if (!sessionStillMatches(session)) {
                clearOwnedLegacy(pending)
                return StepSyncRunOutcome.SUCCESS
            }
            val status = response.statusCode
            if (response.networkError || status == null || status >= 500) return StepSyncRunOutcome.RETRY
            if (status !in 200..299) {
                return if (clearOwnedLegacy(pending)) StepSyncRunOutcome.SUCCESS else StepSyncRunOutcome.RETRY
            }
            val previous = pending
            pending = pending.copy(dailyComplete = true)
            if (!replaceOwnedLegacy(previous, pending, session)) {
                return if (sessionStillMatches(session)) StepSyncRunOutcome.RETRY else StepSyncRunOutcome.SUCCESS
            }
        }
        if (!pending.samplesComplete) {
            if (!sessionStillMatches(session)) {
                clearOwnedLegacy(pending)
                return StepSyncRunOutcome.SUCCESS
            }
            val response = transport.post(
                legacyRequest(session, pending, "/steps/samples", pending.samplesBody)
            )
            if (!sessionStillMatches(session)) {
                clearOwnedLegacy(pending)
                return StepSyncRunOutcome.SUCCESS
            }
            val status = response.statusCode
            if (response.networkError || status == null || status >= 500) return StepSyncRunOutcome.RETRY
            if (status !in 200..299) {
                return if (clearOwnedLegacy(pending)) StepSyncRunOutcome.SUCCESS else StepSyncRunOutcome.RETRY
            }
            val previous = pending
            pending = pending.copy(samplesComplete = true)
            if (!replaceOwnedLegacy(previous, pending, session)) {
                return if (sessionStillMatches(session)) StepSyncRunOutcome.RETRY else StepSyncRunOutcome.SUCCESS
            }
        }
        return if (clearOwnedLegacy(pending)) StepSyncRunOutcome.SUCCESS else StepSyncRunOutcome.RETRY
    }

    private fun legacyRequest(
        session: ValidSession,
        pending: LegacyEnvelope,
        path: String,
        body: String,
    ) = StepSyncHttpRequest(
        url = "${session.backendBaseUrl}$path",
        headers = mapOf(
            "Content-Type" to "application/json",
            "Authorization" to "Bearer ${session.sessionToken}",
            "X-Timezone" to pending.timeZone,
        ),
        body = body,
    )

    private fun createLegacy(
        session: ValidSession,
        timeZone: String,
        v2Body: String,
    ): LegacyEnvelope? = try {
        val source = JSONObject(v2Body)
        val samples = source.optJSONArray("samples") ?: JSONArray()
        LegacyEnvelope(
            ownerId = session.ownerId,
            backendBaseUrl = session.backendBaseUrl,
            timeZone = timeZone,
            dailyBody = JSONObject()
                .put("steps", source.getInt("steps"))
                .put("date", source.getString("date"))
                .put("skipRaceResolution", true)
                .toString(),
            samplesBody = JSONObject().put("samples", samples).toString(),
            dailyComplete = false,
            samplesComplete = samples.length() == 0,
        )
    } catch (_: Exception) {
        null
    }

    private fun negativeCapabilityState(session: ValidSession): CapabilityState {
        if (!sessionStillMatches(session)) return CapabilityState.SESSION_CHANGED
        val raw = state.readNegativeCapability() ?: return CapabilityState.ABSENT
        val parsed = try {
            val json = JSONObject(raw)
            NegativeCapability(
                json.getString("ownerId"),
                json.getString("backendBaseUrl"),
                json.getLong("unsupportedUntilEpochMillis"),
            )
        } catch (_: Exception) {
            if (sessionStillMatches(session) && state.readNegativeCapability() == raw) {
                return if (state.writeNegativeCapability(null)) {
                    CapabilityState.ABSENT
                } else CapabilityState.PERSISTENCE_FAILURE
            }
            return if (sessionStillMatches(session)) {
                CapabilityState.ABSENT
            } else CapabilityState.SESSION_CHANGED
        }
        if (parsed.ownerId != session.ownerId || parsed.backendBaseUrl != session.backendBaseUrl ||
            parsed.unsupportedUntilEpochMillis <= now().toEpochMilli()
        ) {
            if (sessionStillMatches(session) && state.readNegativeCapability() == raw) {
                return if (state.writeNegativeCapability(null)) {
                    CapabilityState.ABSENT
                } else CapabilityState.PERSISTENCE_FAILURE
            }
            return if (sessionStillMatches(session)) {
                CapabilityState.ABSENT
            } else CapabilityState.SESSION_CHANGED
        }
        return CapabilityState.CURRENT
    }

    private fun cacheNegativeCapability(session: ValidSession): Boolean {
        if (!sessionStillMatches(session)) return false
        return state.writeNegativeCapability(
            JSONObject()
                .put("ownerId", session.ownerId)
                .put("backendBaseUrl", session.backendBaseUrl)
                .put("unsupportedUntilEpochMillis", now().plus(24, ChronoUnit.HOURS).toEpochMilli())
                .toString()
        )
    }

    private fun clearNegativeCapabilityIfOwned(session: ValidSession): Boolean {
        if (!sessionStillMatches(session)) return true
        val raw = state.readNegativeCapability() ?: return true
        val parsed = try {
            val json = JSONObject(raw)
            NegativeCapability(
                json.getString("ownerId"),
                json.getString("backendBaseUrl"),
                json.getLong("unsupportedUntilEpochMillis"),
            )
        } catch (_: Exception) {
            return if (state.readNegativeCapability() == raw) state.writeNegativeCapability(null) else true
        }
        if (parsed.ownerId != session.ownerId || parsed.backendBaseUrl != session.backendBaseUrl) {
            return true
        }
        return if (state.readNegativeCapability() == raw) state.writeNegativeCapability(null) else true
    }

    private fun sessionStillMatches(captured: ValidSession): Boolean {
        val current = state.readSession()
        return current.healthAuthorized &&
            current.sessionToken == captured.sessionToken &&
            current.ownerId == captured.ownerId &&
            current.backendBaseUrl?.trimEnd('/') == captured.backendBaseUrl
    }

    private fun clearOwnedV2(expected: V2Envelope): Boolean {
        val raw = state.readPendingV2() ?: return true
        val current = decodeV2(raw) ?: return true
        if (current != expected || state.readPendingV2() != raw) return true
        return state.writePendingV2(null)
    }

    private fun clearOwnedLegacy(expected: LegacyEnvelope): Boolean {
        val raw = state.readPendingLegacy() ?: return true
        val current = decodeLegacy(raw) ?: return true
        if (current != expected || state.readPendingLegacy() != raw) return true
        return state.writePendingLegacy(null)
    }

    private fun replaceOwnedLegacy(
        expected: LegacyEnvelope,
        replacement: LegacyEnvelope,
        session: ValidSession,
    ): Boolean {
        if (!sessionStillMatches(session)) {
            clearOwnedLegacy(expected)
            return false
        }
        val raw = state.readPendingLegacy() ?: return false
        val current = decodeLegacy(raw) ?: return false
        if (current != expected || state.readPendingLegacy() != raw) return false
        return state.writePendingLegacy(replacement.encode())
    }

    private fun decodeV2(raw: String): V2Envelope? = try {
        val json = JSONObject(raw)
        val envelope = V2Envelope(
            json.getString("ownerId"), json.getString("backendBaseUrl"),
            json.getString("idempotencyKey"), json.getString("timeZone"),
            json.getString("body"), json.getLong("createdAtEpochMillis"),
        )
        val body = JSONObject(envelope.body)
        UUID.fromString(envelope.idempotencyKey)
        body.getString("date")
        body.getInt("steps")
        body.getJSONArray("samples")
        envelope.takeIf {
            it.ownerId.isNotBlank() && it.backendBaseUrl.isNotBlank() && it.timeZone.isNotBlank()
        }
    } catch (_: Exception) { null }

    private fun decodeLegacy(raw: String): LegacyEnvelope? = try {
        val json = JSONObject(raw)
        val envelope = LegacyEnvelope(
            json.getString("ownerId"), json.getString("backendBaseUrl"),
            json.getString("timeZone"), json.getString("dailyBody"),
            json.getString("samplesBody"), json.getBoolean("dailyComplete"),
            json.getBoolean("samplesComplete"),
        )
        val daily = JSONObject(envelope.dailyBody)
        val samples = JSONObject(envelope.samplesBody)
        daily.getString("date")
        daily.getInt("steps")
        samples.getJSONArray("samples")
        envelope.takeIf {
            it.ownerId.isNotBlank() && it.backendBaseUrl.isNotBlank() && it.timeZone.isNotBlank()
        }
    } catch (_: Exception) { null }

    private data class ValidSession(
        val sessionToken: String,
        val ownerId: String,
        val backendBaseUrl: String,
    )

    private data class V2Envelope(
        val ownerId: String,
        val backendBaseUrl: String,
        val idempotencyKey: String,
        val timeZone: String,
        val body: String,
        val createdAtEpochMillis: Long,
    ) {
        fun matches(session: ValidSession) =
            ownerId == session.ownerId && backendBaseUrl == session.backendBaseUrl
        fun encode(): String = JSONObject()
            .put("ownerId", ownerId).put("backendBaseUrl", backendBaseUrl)
            .put("idempotencyKey", idempotencyKey).put("timeZone", timeZone)
            .put("body", body).put("createdAtEpochMillis", createdAtEpochMillis).toString()
    }

    private data class LegacyEnvelope(
        val ownerId: String,
        val backendBaseUrl: String,
        val timeZone: String,
        val dailyBody: String,
        val samplesBody: String,
        val dailyComplete: Boolean,
        val samplesComplete: Boolean,
    ) {
        fun matches(session: ValidSession) =
            ownerId == session.ownerId && backendBaseUrl == session.backendBaseUrl
        fun encode(): String = JSONObject()
            .put("ownerId", ownerId).put("backendBaseUrl", backendBaseUrl)
            .put("timeZone", timeZone).put("dailyBody", dailyBody)
            .put("samplesBody", samplesBody).put("dailyComplete", dailyComplete)
            .put("samplesComplete", samplesComplete).toString()
    }

    private data class NegativeCapability(
        val ownerId: String,
        val backendBaseUrl: String,
        val unsupportedUntilEpochMillis: Long,
    )

    private enum class CapabilityState {
        CURRENT,
        ABSENT,
        PERSISTENCE_FAILURE,
        SESSION_CHANGED,
    }

    private fun StepSyncHttpResponse.isRetryable(): Boolean =
        networkError || statusCode == null || statusCode in 500..599

    private fun StepSyncHttpResponse.hasCapabilityMarker(): Boolean = try {
        JSONObject(body ?: "").optString("stepIntakeSemantics") == CAPABILITY
    } catch (_: Exception) { false }

    private fun StepSyncHttpResponse.isAsyncDisabled(): Boolean =
        statusCode == 503 && try {
            JSONObject(body ?: "").optString("code") == "ASYNC_DISABLED"
        } catch (_: Exception) { false }

    companion object {
        private const val CAPABILITY = "CANONICAL_SOURCE_QUEUE_V1"
        private val sharedMutex = Mutex()

        fun completedHourCutoff(now: Instant, zone: ZoneId): Instant =
            now.atZone(zone).truncatedTo(ChronoUnit.HOURS).toInstant()

        fun completedHourRanges(now: Instant, zone: ZoneId): List<Pair<Instant, Instant>> {
            val start = now.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant()
            val cutoff = completedHourCutoff(now, zone)
            val ranges = mutableListOf<Pair<Instant, Instant>>()
            var cursor = start
            while (cursor.isBefore(cutoff)) {
                val end = cursor.plus(1, ChronoUnit.HOURS)
                ranges += cursor to end
                cursor = end
            }
            return ranges
        }
    }
}
