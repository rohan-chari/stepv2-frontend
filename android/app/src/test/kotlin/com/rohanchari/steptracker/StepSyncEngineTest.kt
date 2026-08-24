package com.rohanchari.steptracker

import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import androidx.work.ListenableWorker
import java.time.Instant
import java.time.ZoneId
import java.util.ArrayDeque

class StepSyncEngineTest {
    @Test
    fun `one logical sync sends one combined v2 request with capability headers`() = runBlocking {
        val state = FakeState()
        val health = FakeHealth()
        val transport = FakeTransport(
            responses = ArrayDeque(listOf(markerResponse()))
        )
        val engine = engine(state, health, transport)

        assertEquals(StepSyncRunOutcome.SUCCESS, engine.run())

        assertEquals(1, transport.requests.size)
        val request = transport.requests.single()
        assertEquals("https://example.test/steps/sync-v2", request.url)
        assertEquals("Bearer token", request.headers["Authorization"])
        assertEquals("UTC", request.headers["X-Timezone"])
        assertEquals("1.2.3", request.headers["X-App-Version"])
        assertTrue(request.headers["Idempotency-Key"]?.isNotBlank() == true)
        val body = JSONObject(request.body)
        assertEquals("2026-08-24", body.getString("date"))
        assertEquals(1234, body.getInt("steps"))
        assertEquals(1, body.getJSONArray("samples").length())
        assertNull(state.pendingV2)
    }

    @Test
    fun `ambiguous retry reuses immutable key and body and retains pending when exhausted`() = runBlocking {
        val state = FakeState()
        val transport = FakeTransport(
            responses = ArrayDeque(
                listOf(
                    StepSyncHttpResponse.networkFailure(),
                    StepSyncHttpResponse.networkFailure(),
                )
            )
        )

        assertEquals(StepSyncRunOutcome.RETRY, engine(state, FakeHealth(), transport).run())

        assertEquals(2, transport.requests.size)
        assertEquals(transport.requests[0].body, transport.requests[1].body)
        assertEquals(
            transport.requests[0].headers["Idempotency-Key"],
            transport.requests[1].headers["Idempotency-Key"],
        )
        assertTrue(state.pendingV2?.isNotBlank() == true)
    }

    @Test
    fun `marker-less 202 falls back to staged legacy pair and caches negative capability`() = runBlocking {
        val state = FakeState()
        val transport = FakeTransport(
            responses = ArrayDeque(
                listOf(
                    StepSyncHttpResponse(202, "{}"),
                    StepSyncHttpResponse(200, "{}"),
                    StepSyncHttpResponse(200, "{}"),
                )
            )
        )

        assertEquals(StepSyncRunOutcome.SUCCESS, engine(state, FakeHealth(), transport).run())

        assertEquals(
            listOf("/steps/sync-v2", "/steps", "/steps/samples"),
            transport.requests.map { java.net.URI(it.url).path },
        )
        assertNull(state.pendingV2)
        assertNull(state.pendingLegacy)
        assertTrue(state.negativeCapability?.isNotBlank() == true)
    }

    @Test
    fun `ambiguous v2 never falls back to legacy`() = runBlocking {
        val state = FakeState()
        val transport = FakeTransport(
            responses = ArrayDeque(
                listOf(
                    StepSyncHttpResponse(500, "{}"),
                    StepSyncHttpResponse(503, "{}"),
                )
            )
        )

        assertEquals(StepSyncRunOutcome.RETRY, engine(state, FakeHealth(), transport).run())
        assertEquals(listOf("/steps/sync-v2", "/steps/sync-v2"), transport.requests.map {
            java.net.URI(it.url).path
        })
        assertTrue(state.pendingV2?.isNotBlank() == true)
        assertNull(state.pendingLegacy)
    }

    @Test
    fun `mismatched owner pending is discarded without transmission then fresh owner syncs`() = runBlocking {
        val state = FakeState()
        val oldEnvelope = JSONObject()
            .put("ownerId", "other-user")
            .put("backendBaseUrl", "https://example.test")
            .put("idempotencyKey", "11111111-1111-4111-8111-111111111111")
            .put("timeZone", "UTC")
            .put("body", "{\"date\":\"1999-01-01\",\"steps\":999,\"samples\":[]}")
            .put("createdAtEpochMillis", 1L)
        state.pendingV2 = oldEnvelope.toString()
        val transport = FakeTransport(ArrayDeque(listOf(markerResponse())))

        assertEquals(StepSyncRunOutcome.SUCCESS, engine(state, FakeHealth(), transport).run())

        assertEquals(1, transport.requests.size)
        assertEquals(1234, JSONObject(transport.requests.single().body).getInt("steps"))
        assertNull(state.pendingV2)
    }

    @Test
    fun `shared mutex serializes workers and second rereads state after lock`() = runBlocking {
        val state = FakeState()
        val health = FakeHealth(delayMillis = 30)
        val transport = FakeTransport(
            responses = ArrayDeque(listOf(markerResponse(), markerResponse())),
            delayMillis = 30,
        )
        val first = engine(state, health, transport)
        val second = engine(state, health, transport)

        val a = async { first.run() }
        val b = async { second.run() }
        assertEquals(StepSyncRunOutcome.SUCCESS, a.await())
        assertEquals(StepSyncRunOutcome.SUCCESS, b.await())

        assertEquals(1, transport.maxInFlight)
        assertEquals(16, state.sessionReads)
        assertEquals(2, health.reads)
    }

    @Test
    fun `completed-hour cutoff excludes partial hour across DST gap and repeat`() {
        val zone = ZoneId.of("America/New_York")
        assertEquals(
            Instant.parse("2026-03-08T07:00:00Z"),
            StepSyncEngine.completedHourCutoff(Instant.parse("2026-03-08T07:30:00Z"), zone),
        )
        assertEquals(
            Instant.parse("2026-11-01T06:00:00Z"),
            StepSyncEngine.completedHourCutoff(Instant.parse("2026-11-01T06:30:00Z"), zone),
        )
        assertNotEquals(
            Instant.parse("2026-11-01T05:00:00Z"),
            StepSyncEngine.completedHourCutoff(Instant.parse("2026-11-01T06:30:00Z"), zone),
        )
    }

    @Test
    fun `definite async disabled falls back without retrying v2`() = runBlocking {
        val state = FakeState()
        val transport = FakeTransport(ArrayDeque(listOf(
            StepSyncHttpResponse(503, "{\"code\":\"ASYNC_DISABLED\"}"),
            StepSyncHttpResponse(200, "{}"),
            StepSyncHttpResponse(200, "{}"),
        )))

        assertEquals(StepSyncRunOutcome.SUCCESS, engine(state, FakeHealth(), transport).run())
        assertEquals(
            listOf("/steps/sync-v2", "/steps", "/steps/samples"),
            transport.requests.map { java.net.URI(it.url).path },
        )
    }

    @Test
    fun `conflict creates a fresh key and never falls back`() = runBlocking {
        val state = FakeState()
        val transport = FakeTransport(ArrayDeque(listOf(
            StepSyncHttpResponse(409, "{}"),
            markerResponse(),
        )))
        var key = 0
        val engine = StepSyncEngine(
            state = state,
            health = FakeHealth(),
            transport = transport,
            now = { Instant.parse("2026-08-24T19:37:00Z") },
            newIdempotencyKey = { "key-${++key}" },
            appVersion = "1.2.3",
        )

        assertEquals(StepSyncRunOutcome.SUCCESS, engine.run())
        assertEquals(listOf("key-1", "key-2"), transport.requests.map {
            it.headers["Idempotency-Key"]
        })
        assertFalse(transport.requests.any { java.net.URI(it.url).path == "/steps" })
    }

    @Test
    fun `terminal v2 responses clear pending and never fall back`() = runBlocking {
        for (status in listOf(400, 401, 403, 413, 429)) {
            val state = FakeState()
            val transport = FakeTransport(ArrayDeque(listOf(StepSyncHttpResponse(status, "{}"))))
            assertEquals(StepSyncRunOutcome.SUCCESS, engine(state, FakeHealth(), transport).run())
            assertEquals(1, transport.requests.size)
            assertNull(state.pendingV2)
            assertNull(state.pendingLegacy)
        }
    }

    @Test
    fun `old matching pending envelope has no ttl and replays before fresh read`() = runBlocking {
        val state = FakeState()
        state.pendingV2 = JSONObject()
            .put("ownerId", "user-1")
            .put("backendBaseUrl", "https://example.test")
            .put("idempotencyKey", "11111111-1111-4111-8111-111111111111")
            .put("timeZone", "UTC")
            .put("body", "{\"date\":\"2020-01-01\",\"steps\":1,\"samples\":[]}")
            .put("createdAtEpochMillis", 1L)
            .toString()
        val health = FakeHealth()
        val transport = FakeTransport(ArrayDeque(listOf(markerResponse(), markerResponse())))

        assertEquals(StepSyncRunOutcome.SUCCESS, engine(state, health, transport).run())
        assertEquals(2, transport.requests.size)
        assertEquals(
            "11111111-1111-4111-8111-111111111111",
            transport.requests.first().headers["Idempotency-Key"],
        )
        assertEquals(1, health.reads)
        assertNull(state.pendingV2)
    }

    @Test
    fun `persistence failure prevents network and maps to retry`() = runBlocking {
        val state = FakeState().apply { failNextWrite = true }
        val transport = FakeTransport(ArrayDeque(listOf(markerResponse())))

        assertEquals(StepSyncRunOutcome.RETRY, engine(state, FakeHealth(), transport).run())
        assertTrue(transport.requests.isEmpty())
    }

    @Test
    fun `stale capability cleanup persistence failure prevents network and maps to retry`() = runBlocking {
        val state = FakeState().apply {
            negativeCapability = "not-json"
            failNextWrite = true
        }
        val transport = FakeTransport(ArrayDeque(listOf(markerResponse())))

        assertEquals(StepSyncRunOutcome.RETRY, engine(state, FakeHealth(), transport).run())
        assertTrue(transport.requests.isEmpty())
        assertEquals("not-json", state.negativeCapability)
    }

    @Test
    fun `replacement token mid-flight prevents retry fallback and envelope resurrection`() = runBlocking {
        val state = FakeState()
        val transport = FakeTransport(
            ArrayDeque(listOf(StepSyncHttpResponse(503, "{\"code\":\"ASYNC_DISABLED\"}"))),
            beforeFirstReturn = { state.sessionToken = "replacement-token" },
        )

        assertEquals(StepSyncRunOutcome.SUCCESS, engine(state, FakeHealth(), transport).run())
        assertEquals(1, transport.requests.size)
        assertEquals("Bearer token", transport.requests.single().headers["Authorization"])
        assertNull(state.pendingV2)
        assertNull(state.pendingLegacy)
    }

    @Test
    fun `sign-out mid-flight stops without retry fallback or resurrection`() = runBlocking {
        assertMidflightSessionMutationStops { state ->
            state.sessionToken = null
            state.ownerId = null
        }
    }

    @Test
    fun `account change mid-flight stops without retry fallback or resurrection`() = runBlocking {
        assertMidflightSessionMutationStops { it.ownerId = "user-2" }
    }

    @Test
    fun `backend change mid-flight stops without retry fallback or resurrection`() = runBlocking {
        assertMidflightSessionMutationStops { it.backendBaseUrl = "https://other.test" }
    }

    @Test
    fun `authorization loss mid-flight stops without retry fallback or resurrection`() = runBlocking {
        assertMidflightSessionMutationStops { it.healthAuthorized = false }
    }

    @Test
    fun `session change preserves a newer replacement envelope`() = runBlocking {
        val state = FakeState()
        val replacement = validV2(owner = "user-2", backend = "https://other.test")
        val transport = FakeTransport(
            ArrayDeque(listOf(StepSyncHttpResponse.networkFailure())),
            beforeFirstReturn = {
                state.ownerId = "user-2"
                state.backendBaseUrl = "https://other.test"
                state.pendingV2 = replacement
            },
        )

        assertEquals(StepSyncRunOutcome.SUCCESS, engine(state, FakeHealth(), transport).run())
        assertEquals(1, transport.requests.size)
        assertEquals(replacement, state.pendingV2)
        assertNull(state.pendingLegacy)
    }

    @Test
    fun `corrupt and backend-mismatched envelopes are discarded before fresh intake`() = runBlocking {
        for (pending in listOf("not-json", validV2(backend = "https://old.test"))) {
            val state = FakeState().apply { pendingV2 = pending }
            val transport = FakeTransport(ArrayDeque(listOf(markerResponse())))

            assertEquals(StepSyncRunOutcome.SUCCESS, engine(state, FakeHealth(), transport).run())
            assertEquals(1, transport.requests.size)
            assertEquals(1234, JSONObject(transport.requests.single().body).getInt("steps"))
            assertNull(state.pendingV2)
        }
    }

    @Test
    fun `partial legacy restart resumes samples before a fresh sync`() = runBlocking {
        val state = FakeState()
        val firstTransport = FakeTransport(ArrayDeque(listOf(
            StepSyncHttpResponse(202, "{}"),
            StepSyncHttpResponse(200, "{}"),
            StepSyncHttpResponse.networkFailure(),
        )))
        assertEquals(StepSyncRunOutcome.RETRY, engine(state, FakeHealth(), firstTransport).run())
        assertTrue(state.pendingLegacy?.contains("\"dailyComplete\":true") == true)

        val secondTransport = FakeTransport(ArrayDeque(listOf(
            StepSyncHttpResponse(200, "{}"), // remaining samples
            StepSyncHttpResponse(200, "{}"), // fresh negative-cache daily
            StepSyncHttpResponse(200, "{}"), // fresh negative-cache samples
        )))
        assertEquals(StepSyncRunOutcome.SUCCESS, engine(state, FakeHealth(), secondTransport).run())
        assertEquals(
            listOf("/steps/samples", "/steps", "/steps/samples"),
            secondTransport.requests.map { java.net.URI(it.url).path },
        )
        assertNull(state.pendingLegacy)
    }

    @Test
    fun `expired negative cache probes v2 and marker is revalidated every time`() = runBlocking {
        val state = FakeState()
        state.negativeCapability = JSONObject()
            .put("ownerId", "user-1")
            .put("backendBaseUrl", "https://example.test")
            .put("unsupportedUntilEpochMillis", 1L)
            .toString()
        val transport = FakeTransport(ArrayDeque(listOf(markerResponse())))
        assertEquals(StepSyncRunOutcome.SUCCESS, engine(state, FakeHealth(), transport).run())
        assertEquals("/steps/sync-v2", java.net.URI(transport.requests.single().url).path)

        val rollbackTransport = FakeTransport(ArrayDeque(listOf(
            StepSyncHttpResponse(202, "{}"),
            StepSyncHttpResponse(200, "{}"),
            StepSyncHttpResponse(200, "{}"),
        )))
        assertEquals(StepSyncRunOutcome.SUCCESS, engine(state, FakeHealth(), rollbackTransport).run())
        assertEquals(
            listOf("/steps/sync-v2", "/steps", "/steps/samples"),
            rollbackTransport.requests.map { java.net.URI(it.url).path },
        )
    }

    @Test
    fun `worker result mapping uses actual WorkManager terminal classes`() {
        assertTrue(workerResultFor(StepSyncRunOutcome.SUCCESS) is ListenableWorker.Result.Success)
        assertTrue(workerResultFor(StepSyncRunOutcome.RETRY) is ListenableWorker.Result.Retry)
    }

    @Test
    fun `actual worker health seam treats revoked live permission as success without request`() = runBlocking {
        val state = FakeState().apply { healthAuthorized = true }
        val transport = FakeTransport(ArrayDeque(listOf(markerResponse())))
        val health = AndroidStepSyncHealth(
            FakeAndroidHealthGateway(hasStepReadPermission = false),
        )

        val result = runStepSyncWorker(
            state = state,
            health = health,
            transport = transport,
            now = { Instant.parse("2026-08-24T19:37:00Z") },
            zone = { ZoneId.of("UTC") },
            appVersion = "1.2.3",
        )

        assertTrue(result is ListenableWorker.Result.Success)
        assertTrue(transport.requests.isEmpty())
        assertEquals(0, state.writeCalls)
        assertNull(state.pendingV2)
        assertNull(state.pendingLegacy)
    }

    @Test
    fun `actual worker health seam retries transient daily read without request or zero upload`() = runBlocking {
        val state = FakeState().apply { healthAuthorized = true }
        val transport = FakeTransport(ArrayDeque(listOf(markerResponse())))
        val health = AndroidStepSyncHealth(
            FakeAndroidHealthGateway(
                hasStepReadPermission = true,
                dailyFailure = IllegalStateException("Health Connect temporarily unavailable"),
            ),
        )

        val result = runStepSyncWorker(
            state = state,
            health = health,
            transport = transport,
            now = { Instant.parse("2026-08-24T19:37:00Z") },
            zone = { ZoneId.of("UTC") },
            appVersion = "1.2.3",
        )

        assertTrue(result is ListenableWorker.Result.Retry)
        assertTrue(transport.requests.isEmpty())
        assertEquals(0, state.writeCalls)
        assertNull(state.pendingV2)
        assertNull(state.pendingLegacy)
    }

    @Test
    fun `generated completed-hour ranges cover DST gap and repeated hour exactly`() {
        val zone = ZoneId.of("America/New_York")
        val spring = StepSyncEngine.completedHourRanges(
            Instant.parse("2026-03-08T07:30:00Z"), zone,
        )
        assertEquals(listOf(
            Instant.parse("2026-03-08T05:00:00Z") to Instant.parse("2026-03-08T06:00:00Z"),
            Instant.parse("2026-03-08T06:00:00Z") to Instant.parse("2026-03-08T07:00:00Z"),
        ), spring)

        val fall = StepSyncEngine.completedHourRanges(
            Instant.parse("2026-11-01T06:30:00Z"), zone,
        )
        assertEquals(listOf(
            Instant.parse("2026-11-01T04:00:00Z") to Instant.parse("2026-11-01T05:00:00Z"),
            Instant.parse("2026-11-01T05:00:00Z") to Instant.parse("2026-11-01T06:00:00Z"),
        ), fall)
    }

    private fun engine(
        state: FakeState,
        health: FakeHealth,
        transport: FakeTransport,
    ) = StepSyncEngine(
        state = state,
        health = health,
        transport = transport,
        now = { Instant.parse("2026-08-24T19:37:00Z") },
        newIdempotencyKey = { "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" },
        appVersion = "1.2.3",
    )

    private fun markerResponse() = StepSyncHttpResponse(
        202,
        "{\"stepIntakeSemantics\":\"CANONICAL_SOURCE_QUEUE_V1\"}",
    )

    private fun validV2(
        owner: String = "user-1",
        backend: String = "https://example.test",
    ): String = JSONObject()
        .put("ownerId", owner)
        .put("backendBaseUrl", backend)
        .put("idempotencyKey", "11111111-1111-4111-8111-111111111111")
        .put("timeZone", "UTC")
        .put("body", "{\"date\":\"1999-01-01\",\"steps\":999,\"samples\":[]}")
        .put("createdAtEpochMillis", 1L)
        .toString()

    private suspend fun assertMidflightSessionMutationStops(mutate: (FakeState) -> Unit) {
        val state = FakeState()
        val transport = FakeTransport(
            ArrayDeque(listOf(StepSyncHttpResponse(503, "{\"code\":\"ASYNC_DISABLED\"}"))),
            beforeFirstReturn = { mutate(state) },
        )
        assertEquals(StepSyncRunOutcome.SUCCESS, engine(state, FakeHealth(), transport).run())
        assertEquals(1, transport.requests.size)
        assertNull(state.pendingV2)
        assertNull(state.pendingLegacy)
    }
}

private class FakeAndroidHealthGateway(
    private val hasStepReadPermission: Boolean,
    private val dailyFailure: Exception? = null,
) : AndroidStepSyncHealthGateway {
    private var reads = 0

    override suspend fun hasStepReadPermission(): Boolean = hasStepReadPermission

    override suspend fun accurateSteps(start: Instant, end: Instant): Int {
        reads += 1
        if (reads == 1) dailyFailure?.let { throw it }
        return 1234
    }
}

private class FakeState : StepSyncState {
    var pendingV2: String? = null
    var pendingLegacy: String? = null
    var negativeCapability: String? = null
    var sessionReads = 0
    var sessionToken: String? = "token"
    var ownerId: String? = "user-1"
    var backendBaseUrl: String? = "https://example.test"
    var healthAuthorized = true
    var failNextWrite = false
    var writeCalls = 0

    override fun readSession(): StepSyncSession {
        sessionReads += 1
        return StepSyncSession(
            sessionToken = sessionToken,
            ownerId = ownerId,
            backendBaseUrl = backendBaseUrl,
            healthAuthorized = healthAuthorized,
        )
    }

    override fun readPendingV2(): String? = pendingV2
    override fun writePendingV2(value: String?): Boolean = write { pendingV2 = value }
    override fun readPendingLegacy(): String? = pendingLegacy
    override fun writePendingLegacy(value: String?): Boolean = write { pendingLegacy = value }
    override fun readNegativeCapability(): String? = negativeCapability
    override fun writeNegativeCapability(value: String?): Boolean = write { negativeCapability = value }

    private fun write(action: () -> Unit): Boolean {
        writeCalls += 1
        if (failNextWrite) {
            failNextWrite = false
            return false
        }
        action()
        return true
    }
}

private class FakeHealth(private val delayMillis: Long = 0) : StepSyncHealth {
    var reads = 0

    override suspend fun readSnapshot(now: Instant, zone: ZoneId): StepSyncSnapshot {
        reads += 1
        if (delayMillis > 0) delay(delayMillis)
        return StepSyncSnapshot(
            date = "2026-08-24",
            steps = 1234,
            samples = listOf(
                StepSyncSample(
                    "2026-08-24T18:00:00Z",
                    "2026-08-24T19:00:00Z",
                    321,
                )
            ),
            timeZone = "UTC",
        )
    }
}

private class FakeTransport(
    private val responses: ArrayDeque<StepSyncHttpResponse>,
    private val delayMillis: Long = 0,
    private val beforeFirstReturn: (() -> Unit)? = null,
) : StepSyncTransport {
    val requests = mutableListOf<StepSyncHttpRequest>()
    var inFlight = 0
    var maxInFlight = 0

    override suspend fun post(request: StepSyncHttpRequest): StepSyncHttpResponse {
        requests += request
        inFlight += 1
        maxInFlight = maxOf(maxInFlight, inFlight)
        if (delayMillis > 0) delay(delayMillis)
        if (requests.size == 1) beforeFirstReturn?.invoke()
        inFlight -= 1
        return responses.removeFirst()
    }
}
