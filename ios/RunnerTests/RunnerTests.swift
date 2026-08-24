import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testCombinedV2RequestCarriesImmutableBodyHeadersAndCapabilityMarker() {
    let state = MockStateStore(
      sessionToken: "session-token",
      backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"),
      healthAuthorized: true
    )
    let poster = MockPoster(
      responses: [
        BackgroundStepHTTPResponse(
          statusCode: 202,
          body: Data("{\"stepIntakeSemantics\":\"CANONICAL_SOURCE_QUEUE_V1\"}".utf8),
          error: nil
        )
      ]
    )
    let reader = MockStepReader(
      result: .success([BackgroundDailyStep(date: "2026-08-24", steps: 1234)]),
      hourlyResult: .success([[
        "periodStart": "2026-08-24T18:00:00Z",
        "periodEnd": "2026-08-24T19:00:00Z",
        "steps": 321,
      ]])
    )
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: reader,
      poster: poster,
      now: { isoDate("2026-08-24T19:37:00Z") },
      timeZoneIdentifier: { "UTC" },
      appVersion: { "1.2.3" },
      newIdempotencyKey: { "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }
    )

    let done = expectation(description: "sync")
    coordinator.performSync { result in
      XCTAssertEqual(result, .success)
      done.fulfill()
    }
    wait(for: [done], timeout: 1)

    XCTAssertEqual(poster.v2Requests.count, 1)
    let request = poster.v2Requests[0]
    XCTAssertEqual(request.idempotencyKey, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    XCTAssertEqual(request.timeZone, "UTC")
    XCTAssertEqual(request.appVersion, "1.2.3")
    let payload = try! JSONSerialization.jsonObject(with: request.body) as! [String: Any]
    XCTAssertEqual(payload["date"] as? String, "2026-08-24")
    XCTAssertEqual(payload["steps"] as? Int, 1234)
    XCTAssertEqual((payload["samples"] as? [[String: Any]])?.count, 1)
    XCTAssertNil(state.pendingV2Envelope)
  }

  func testAmbiguousV2RetryUsesExactKeyAndBodyAndNeverFallsBack() {
    let state = MockStateStore(
      sessionToken: "session-token",
      backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"),
      healthAuthorized: true
    )
    let poster = MockPoster(responses: [
      BackgroundStepHTTPResponse(statusCode: nil, body: nil, error: TestError.failed),
      BackgroundStepHTTPResponse(statusCode: 503, body: Data("{}".utf8), error: nil),
    ])
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: MockStepReader(
        result: .success([BackgroundDailyStep(date: "2026-08-24", steps: 1234)])
      ),
      poster: poster,
      now: { isoDate("2026-08-24T19:37:00Z") },
      newIdempotencyKey: { "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }
    )

    let done = expectation(description: "sync")
    coordinator.performSync { result in
      XCTAssertEqual(result, .failed)
      done.fulfill()
    }
    wait(for: [done], timeout: 1)

    XCTAssertEqual(poster.v2Requests.count, 2)
    XCTAssertEqual(poster.v2Requests[0].idempotencyKey, poster.v2Requests[1].idempotencyKey)
    XCTAssertEqual(poster.v2Requests[0].body, poster.v2Requests[1].body)
    XCTAssertTrue(poster.capturedPosts.isEmpty)
    XCTAssertNotNil(state.pendingV2Envelope)
  }

  func testMarkerless202RunsStagedLegacyFallbackAndCachesNegativeCapability() {
    let state = MockStateStore(
      sessionToken: "session-token",
      backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"),
      healthAuthorized: true
    )
    let poster = MockPoster(
      statusCode: 200,
      responses: [
        BackgroundStepHTTPResponse(statusCode: 202, body: Data("{}".utf8), error: nil)
      ]
    )
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: MockStepReader(
        result: .success([BackgroundDailyStep(date: "2026-08-24", steps: 1234)]),
        hourlyResult: .success([[
          "periodStart": "2026-08-24T18:00:00Z",
          "periodEnd": "2026-08-24T19:00:00Z",
          "steps": 321,
        ]])
      ),
      poster: poster,
      now: { isoDate("2026-08-24T19:37:00Z") }
    )

    let done = expectation(description: "sync")
    coordinator.performSync { result in
      XCTAssertEqual(result, .success)
      done.fulfill()
    }
    wait(for: [done], timeout: 1)

    XCTAssertEqual(poster.v2Requests.count, 1)
    XCTAssertEqual(poster.capturedPosts, [BackgroundDailyStep(date: "2026-08-24", steps: 1234)])
    XCTAssertEqual(poster.samplePostCount, 1)
    XCTAssertNil(state.pendingLegacyEnvelope)
    XCTAssertNotNil(state.negativeCapability)
  }

  func testOverlappingTriggersShareOneActiveRequestAndOneTrailingFreshRun() {
    let state = MockStateStore(
      sessionToken: "session-token",
      backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"),
      healthAuthorized: true
    )
    let poster = DeferredPoster()
    let reader = MockStepReader(
      result: .success([BackgroundDailyStep(date: "2026-08-24", steps: 1234)])
    )
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: reader,
      poster: poster,
      now: { isoDate("2026-08-24T19:37:00Z") }
    )
    let first = expectation(description: "first completion")
    let second = expectation(description: "second completion")
    var firstCalls = 0
    var secondCalls = 0

    coordinator.performSync { _ in firstCalls += 1; first.fulfill() }
    coordinator.performSync { _ in secondCalls += 1; second.fulfill() }
    waitUntil { poster.v2Requests.count == 1 }
    XCTAssertEqual(poster.v2Requests.count, 1)

    poster.completeNextWithMarker()
    waitUntil { poster.v2Requests.count == 2 }
    poster.completeNextWithMarker()
    wait(for: [first, second], timeout: 1)

    XCTAssertEqual(poster.v2Requests.count, 2)
    XCTAssertEqual(firstCalls, 1)
    XCTAssertEqual(secondCalls, 1)
  }

  func testInsufficientBudgetDetachesTrailingCompletionWithoutSecondRequest() {
    let state = MockStateStore(
      sessionToken: "session-token",
      backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"),
      healthAuthorized: true
    )
    let poster = DeferredPoster()
    var hasBudget = true
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: MockStepReader(
        result: .success([BackgroundDailyStep(date: "2026-08-24", steps: 1234)])
      ),
      poster: poster,
      now: { isoDate("2026-08-24T19:37:00Z") },
      hasExecutionBudget: { hasBudget }
    )
    let first = expectation(description: "first completion")
    let second = expectation(description: "trailing completion")
    coordinator.performSync { _ in first.fulfill() }
    coordinator.performSync { result in
      XCTAssertEqual(result, .noData)
      second.fulfill()
    }
    waitUntil { poster.v2Requests.count == 1 }
    hasBudget = false
    poster.completeNextWithMarker()
    wait(for: [first, second], timeout: 1)
    XCTAssertEqual(poster.v2Requests.count, 1)
  }

  func testProcessRestartReplaysPendingEnvelopeBeforeOneFreshHealthRead() {
    let state = MockStateStore(
      sessionToken: "session-token",
      backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"),
      healthAuthorized: true
    )
    let firstPoster = MockPoster(responses: [
      BackgroundStepHTTPResponse(statusCode: nil, body: nil, error: TestError.failed),
      BackgroundStepHTTPResponse(statusCode: nil, body: nil, error: TestError.failed),
    ])
    let first = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: MockStepReader(
        result: .success([BackgroundDailyStep(date: "2026-08-24", steps: 1200)])
      ),
      poster: firstPoster,
      now: { isoDate("2026-08-24T19:37:00Z") },
      newIdempotencyKey: { "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }
    )
    let failed = expectation(description: "ambiguous first run")
    first.performSync { _ in failed.fulfill() }
    wait(for: [failed], timeout: 1)
    XCTAssertNotNil(state.pendingV2Envelope)
    var ancientJSON = try! JSONSerialization.jsonObject(
      with: Data(state.pendingV2Envelope!.utf8)
    ) as! [String: Any]
    ancientJSON["createdAt"] = -10_000_000_000.0
    state.pendingV2Envelope = String(
      data: try! JSONSerialization.data(withJSONObject: ancientJSON), encoding: .utf8
    )

    let secondPoster = MockPoster(responses: [
      markerResponse(),
      markerResponse(),
    ])
    let secondReader = MockStepReader(
      result: .success([BackgroundDailyStep(date: "2026-08-24", steps: 1300)])
    )
    let second = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: secondReader,
      poster: secondPoster,
      now: { isoDate("2026-08-24T19:42:00Z") },
      newIdempotencyKey: { "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" }
    )
    let recovered = expectation(description: "recovered")
    second.performSync { result in XCTAssertEqual(result, .success); recovered.fulfill() }
    wait(for: [recovered], timeout: 1)

    XCTAssertEqual(secondPoster.v2Requests.count, 2)
    XCTAssertEqual(secondPoster.v2Requests[0].idempotencyKey, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    XCTAssertEqual(secondPoster.v2Requests[1].idempotencyKey, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
    XCTAssertEqual(
      (try! JSONSerialization.jsonObject(with: secondPoster.v2Requests[0].body) as! [String: Any])["steps"] as? Int,
      1200
    )
    XCTAssertEqual(
      (try! JSONSerialization.jsonObject(with: secondPoster.v2Requests[1].body) as! [String: Any])["steps"] as? Int,
      1300
    )
    XCTAssertEqual(secondReader.capturedSyncDays.count, 1)
    XCTAssertNil(state.pendingV2Envelope)
  }

  func testConflictClearsPendingAndBuildsFreshKeyWithoutLegacyFallback() {
    let state = MockStateStore(
      sessionToken: "session-token",
      backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"),
      healthAuthorized: true
    )
    let poster = MockPoster(responses: [
      BackgroundStepHTTPResponse(statusCode: 409, body: Data("{}".utf8), error: nil),
      markerResponse(),
    ])
    var keys = ["aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"]
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: MockStepReader(
        result: .success([BackgroundDailyStep(date: "2026-08-24", steps: 1234)])
      ),
      poster: poster,
      now: { isoDate("2026-08-24T19:37:00Z") },
      newIdempotencyKey: { keys.removeFirst() }
    )
    let done = expectation(description: "fresh after conflict")
    coordinator.performSync { result in XCTAssertEqual(result, .success); done.fulfill() }
    wait(for: [done], timeout: 1)
    XCTAssertEqual(poster.v2Requests.map(\.idempotencyKey), [
      "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    ])
    XCTAssertTrue(poster.capturedPosts.isEmpty)
    XCTAssertNil(state.pendingV2Envelope)
  }

  func testBackgroundCompletionGateSettlesExpirationNetworkRaceExactlyOnce() {
    let gate = BackgroundTaskCompletionGate()
    let start = DispatchSemaphore(value: 0)
    let settled = expectation(description: "one terminal completion")
    settled.expectedFulfillmentCount = 1
    let lock = NSLock()
    var values: [Bool] = []

    for value in [false, true] {
      DispatchQueue.global().async {
        start.wait()
        gate.finish(value) { result in
          lock.lock()
          values.append(result)
          lock.unlock()
          settled.fulfill()
        }
      }
    }
    start.signal()
    start.signal()
    wait(for: [settled], timeout: 1)
    XCTAssertEqual(values.count, 1)
  }

  func testExpirationWinnerDoesNotCancelOtherAttachedSyncWork() {
    let state = MockStateStore(
      sessionToken: "session-token", backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"), healthAuthorized: true
    )
    let poster = DeferredPoster()
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: MockStepReader(result: .success([
        BackgroundDailyStep(date: "2026-08-24", steps: 1234)
      ])), poster: poster, now: { isoDate("2026-08-24T19:37:00Z") }
    )
    let completionGate = BackgroundTaskCompletionGate()
    let bgSettled = expectation(description: "BG task settled once")
    bgSettled.expectedFulfillmentCount = 1
    var bgValues: [Bool] = []
    let attached = expectation(description: "attached sync callbacks")
    attached.expectedFulfillmentCount = 2

    coordinator.performSync { result in
      completionGate.finish(result != .failed) { bgValues.append($0); bgSettled.fulfill() }
      attached.fulfill()
    }
    coordinator.performSync { _ in attached.fulfill() }
    waitUntil { poster.v2Requests.count == 1 }
    completionGate.finish(false) { bgValues.append($0); bgSettled.fulfill() }
    poster.completeNextWithMarker()
    waitUntil { poster.v2Requests.count == 2 }
    poster.completeNextWithMarker()
    wait(for: [bgSettled, attached], timeout: 1)

    XCTAssertEqual(bgValues, [false])
    XCTAssertEqual(poster.v2Requests.count, 2)
  }

  func testSessionChangeDuringV2PreventsRetryFallbackAndReplacementTokenRequest() {
    let state = MockStateStore(
      sessionToken: "old-token",
      backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"),
      healthAuthorized: true
    )
    let poster = DeferredPoster()
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: MockStepReader(
        result: .success([BackgroundDailyStep(date: "2026-08-24", steps: 1234)])
      ),
      poster: poster,
      now: { isoDate("2026-08-24T19:37:00Z") }
    )
    let done = expectation(description: "session change completion")
    coordinator.performSync { result in
      XCTAssertEqual(result, .noData)
      done.fulfill()
    }
    waitUntil { poster.v2Requests.count == 1 }
    state.sessionToken = "replacement-token"
    poster.completeNext(BackgroundStepHTTPResponse(
      statusCode: 503,
      body: Data("{\"code\":\"ASYNC_DISABLED\"}".utf8),
      error: nil
    ))
    wait(for: [done], timeout: 1)

    XCTAssertEqual(poster.v2Requests.count, 1)
    XCTAssertTrue(poster.legacyRequests.isEmpty)
    XCTAssertNil(state.pendingV2Envelope)
  }

  func testSessionChangePreservesANewerReplacementEnvelope() {
    let state = MockStateStore(
      sessionToken: "old-token", backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"), healthAuthorized: true
    )
    let poster = DeferredPoster()
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: MockStepReader(result: .success([
        BackgroundDailyStep(date: "2026-08-24", steps: 1234)
      ])), poster: poster, now: { isoDate("2026-08-24T19:37:00Z") }
    )
    let done = expectation(description: "replacement envelope preserved")
    coordinator.performSync { XCTAssertEqual($0, .noData); done.fulfill() }
    waitUntil { poster.v2Requests.count == 1 }

    var replacementJSON = try! JSONSerialization.jsonObject(
      with: Data(state.pendingV2Envelope!.utf8)
    ) as! [String: Any]
    replacementJSON["ownerID"] = "user-2"
    replacementJSON["backendBaseURL"] = "https://other.test"
    let replacement = String(
      data: try! JSONSerialization.data(withJSONObject: replacementJSON), encoding: .utf8
    )!
    state.backendUserID = "user-2"
    state.backendBaseURL = URL(string: "https://other.test")
    state.pendingV2Envelope = replacement
    poster.completeNext(BackgroundStepHTTPResponse(statusCode: nil, body: nil, error: TestError.failed))
    wait(for: [done], timeout: 1)

    XCTAssertEqual(poster.v2Requests.count, 1)
    XCTAssertEqual(state.pendingV2Envelope, replacement)
    XCTAssertNil(state.pendingLegacyEnvelope)
  }

  func testIOSResponseClassifierTerminalTable() {
    let cases: [(Int, String, Bool, BackgroundStepSyncResult)] = [
      (404, "{}", true, .success),
      (503, "{\"code\":\"ASYNC_DISABLED\"}", true, .success),
      (400, "{}", false, .failed),
      (401, "{}", false, .noData),
      (403, "{}", false, .noData),
      (413, "{}", false, .failed),
      (429, "{}", false, .noData),
    ]
    for (status, body, expectsLegacy, expectedResult) in cases {
      let state = MockStateStore(
        sessionToken: "session-token",
        backendUserID: "user-1",
        backendBaseURL: URL(string: "https://example.test"),
        healthAuthorized: true
      )
      let poster = MockPoster(
        responses: [BackgroundStepHTTPResponse(
          statusCode: status, body: Data(body.utf8), error: nil
        )]
      )
      let coordinator = BackgroundStepSyncCoordinator(
        stateStore: state,
        stepReader: MockStepReader(
          result: .success([BackgroundDailyStep(date: "2026-08-24", steps: 1234)])
        ),
        poster: poster,
        now: { isoDate("2026-08-24T19:37:00Z") }
      )
      let done = expectation(description: "terminal \(status)")
      coordinator.performSync { result in
        XCTAssertEqual(result, expectedResult, "status \(status)")
        done.fulfill()
      }
      wait(for: [done], timeout: 1)
      XCTAssertEqual(!poster.legacyRequests.isEmpty, expectsLegacy, "status \(status)")
      XCTAssertNil(state.pendingV2Envelope, "status \(status)")
    }
  }

  func testSignOutMidFlightStopsWithoutRetryFallbackOrResurrection() {
    assertMidFlightSessionMutationStops { state in
      state.sessionToken = nil
      state.backendUserID = nil
    }
  }

  func testAccountChangeMidFlightStopsWithoutRetryFallbackOrResurrection() {
    assertMidFlightSessionMutationStops { $0.backendUserID = "user-2" }
  }

  func testBackendChangeMidFlightStopsWithoutRetryFallbackOrResurrection() {
    assertMidFlightSessionMutationStops { $0.backendBaseURL = URL(string: "https://other.test") }
  }

  func testAuthorizationLossMidFlightStopsWithoutRetryFallbackOrResurrection() {
    assertMidFlightSessionMutationStops { $0.healthAuthorized = false }
  }

  func testPartialLegacyRestartResumesSamplesBeforeFreshSync() {
    let state = MockStateStore(
      sessionToken: "session-token", backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"), healthAuthorized: true
    )
    let firstPoster = MockPoster(
      responses: [BackgroundStepHTTPResponse(statusCode: 202, body: Data("{}".utf8), error: nil)],
      legacyResponses: [
        BackgroundStepHTTPResponse(statusCode: 200, body: Data("{}".utf8), error: nil),
        BackgroundStepHTTPResponse(statusCode: nil, body: nil, error: TestError.failed),
      ]
    )
    let reader = MockStepReader(
      result: .success([BackgroundDailyStep(date: "2026-08-24", steps: 1234)]),
      hourlyResult: .success([["periodStart": "2026-08-24T18:00:00Z",
                               "periodEnd": "2026-08-24T19:00:00Z", "steps": 321]])
    )
    let first = BackgroundStepSyncCoordinator(
      stateStore: state, stepReader: reader, poster: firstPoster,
      now: { isoDate("2026-08-24T19:37:00Z") }
    )
    let firstDone = expectation(description: "partial legacy")
    first.performSync { XCTAssertEqual($0, .failed); firstDone.fulfill() }
    wait(for: [firstDone], timeout: 1)
    XCTAssertTrue(state.pendingLegacyEnvelope?.contains("\"dailyComplete\":true") == true)

    let secondPoster = MockPoster(legacyResponses: [
      BackgroundStepHTTPResponse(statusCode: 200, body: Data("{}".utf8), error: nil),
      BackgroundStepHTTPResponse(statusCode: 200, body: Data("{}".utf8), error: nil),
      BackgroundStepHTTPResponse(statusCode: 200, body: Data("{}".utf8), error: nil),
    ])
    let second = BackgroundStepSyncCoordinator(
      stateStore: state, stepReader: reader, poster: secondPoster,
      now: { isoDate("2026-08-24T19:37:00Z") }
    )
    let secondDone = expectation(description: "legacy recovery")
    second.performSync { XCTAssertEqual($0, .success); secondDone.fulfill() }
    wait(for: [secondDone], timeout: 1)
    XCTAssertEqual(secondPoster.legacyRequests.map(\.path), [
      "/steps/samples", "/steps", "/steps/samples"
    ])
    XCTAssertNil(state.pendingLegacyEnvelope)
  }

  func testCorruptAndBackendMismatchedV2EnvelopesAreNeverTransmitted() {
    let seedState = MockStateStore(
      sessionToken: "session-token", backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"), healthAuthorized: true
    )
    let seedPoster = DeferredPoster()
    let seed = BackgroundStepSyncCoordinator(
      stateStore: seedState,
      stepReader: MockStepReader(result: .success([
        BackgroundDailyStep(date: "2026-08-24", steps: 1234)
      ])), poster: seedPoster, now: { isoDate("2026-08-24T19:37:00Z") }
    )
    let seeded = expectation(description: "seeded")
    seed.performSync { _ in seeded.fulfill() }
    waitUntil { seedPoster.v2Requests.count == 1 }
    let validRaw = seedState.pendingV2Envelope!
    seedPoster.completeNextWithMarker()
    wait(for: [seeded], timeout: 1)

    var mismatchJSON = try! JSONSerialization.jsonObject(with: Data(validRaw.utf8)) as! [String: Any]
    mismatchJSON["backendBaseURL"] = "https://old.test"
    let mismatchRaw = String(data: try! JSONSerialization.data(withJSONObject: mismatchJSON), encoding: .utf8)!
    for pending in ["not-json", mismatchRaw] {
      let state = MockStateStore(
        sessionToken: "session-token", backendUserID: "user-1",
        backendBaseURL: URL(string: "https://example.test"), healthAuthorized: true,
        pendingV2Envelope: pending
      )
      let poster = MockPoster()
      let coordinator = BackgroundStepSyncCoordinator(
        stateStore: state,
        stepReader: MockStepReader(result: .success([
          BackgroundDailyStep(date: "2026-08-24", steps: 1234)
        ])), poster: poster, now: { isoDate("2026-08-24T19:37:00Z") }
      )
      let done = expectation(description: "discard invalid")
      coordinator.performSync { XCTAssertEqual($0, .success); done.fulfill() }
      wait(for: [done], timeout: 1)
      XCTAssertEqual(poster.v2Requests.count, 1)
      XCTAssertEqual(
        (try! JSONSerialization.jsonObject(with: poster.v2Requests[0].body) as! [String: Any])["steps"] as? Int,
        1234
      )
    }
  }

  func testExpiredNegativeCacheReprobesAndMarkerIsRevalidated() {
    let state = MockStateStore(
      sessionToken: "session-token", backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"), healthAuthorized: true
    )
    let fallback = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: MockStepReader(result: .success([
        BackgroundDailyStep(date: "2026-08-24", steps: 1234)
      ])), poster: MockPoster(responses: [
        BackgroundStepHTTPResponse(statusCode: 202, body: Data("{}".utf8), error: nil)
      ]), now: { isoDate("2026-08-24T19:37:00Z") }
    )
    let cached = expectation(description: "negative cached")
    fallback.performSync { _ in cached.fulfill() }
    wait(for: [cached], timeout: 1)
    var cacheJSON = try! JSONSerialization.jsonObject(
      with: Data(state.negativeCapability!.utf8)
    ) as! [String: Any]
    cacheJSON["unsupportedUntil"] = 0
    state.negativeCapability = String(
      data: try! JSONSerialization.data(withJSONObject: cacheJSON), encoding: .utf8
    )

    let markerPoster = MockPoster(responses: [markerResponse()])
    let markerProbe = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: MockStepReader(result: .success([
        BackgroundDailyStep(date: "2026-08-24", steps: 1234)
      ])), poster: markerPoster, now: { isoDate("2026-08-24T19:37:00Z") }
    )
    let markerDone = expectation(description: "marker probe")
    markerProbe.performSync { _ in markerDone.fulfill() }
    wait(for: [markerDone], timeout: 1)
    XCTAssertEqual(markerPoster.v2Requests.count, 1)

    let rollbackPoster = MockPoster(responses: [
      BackgroundStepHTTPResponse(statusCode: 202, body: Data("{}".utf8), error: nil)
    ])
    let rollback = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: MockStepReader(result: .success([
        BackgroundDailyStep(date: "2026-08-24", steps: 1234)
      ])), poster: rollbackPoster, now: { isoDate("2026-08-24T19:37:00Z") }
    )
    let rollbackDone = expectation(description: "marker rollback")
    rollback.performSync { _ in rollbackDone.fulfill() }
    wait(for: [rollbackDone], timeout: 1)
    XCTAssertEqual(rollbackPoster.v2Requests.count, 1)
    XCTAssertEqual(rollbackPoster.legacyRequests.map(\.path), ["/steps"])
  }

  private func assertMidFlightSessionMutationStops(
    _ mutate: @escaping (MockStateStore) -> Void
  ) {
    let state = MockStateStore(
      sessionToken: "old-token", backendUserID: "user-1",
      backendBaseURL: URL(string: "https://example.test"), healthAuthorized: true
    )
    let poster = DeferredPoster()
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: state,
      stepReader: MockStepReader(result: .success([
        BackgroundDailyStep(date: "2026-08-24", steps: 1234)
      ])), poster: poster, now: { isoDate("2026-08-24T19:37:00Z") }
    )
    let done = expectation(description: "session mutation")
    coordinator.performSync { XCTAssertEqual($0, .noData); done.fulfill() }
    waitUntil { poster.v2Requests.count == 1 }
    mutate(state)
    poster.completeNext(BackgroundStepHTTPResponse(
      statusCode: 503, body: Data("{\"code\":\"ASYNC_DISABLED\"}".utf8), error: nil
    ))
    wait(for: [done], timeout: 1)
    XCTAssertEqual(poster.v2Requests.count, 1)
    XCTAssertTrue(poster.legacyRequests.isEmpty)
    XCTAssertNil(state.pendingV2Envelope)
    XCTAssertNil(state.pendingLegacyEnvelope)
  }

  func testPerformSyncReturnsNoDataWhenSessionTokenIsMissing() {
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: MockStateStore(
        sessionToken: nil,
        backendBaseURL: URL(string: "http://127.0.0.1:3000"),
        healthAuthorized: true
      ),
      stepReader: MockStepReader(result: .success([
        BackgroundDailyStep(date: "2026-03-19", steps: 1234)
      ])),
      poster: MockPoster()
    )

    let expectation = expectation(description: "sync completion")
    coordinator.performSync { result in
      XCTAssertEqual(result, .noData)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }

  func testStateStoreReadsFlutterPrefixedKeys() {
    // Fix C1 seam test: crosses the Dart-write / Swift-read boundary. Dart's legacy
    // shared_preferences writes "flutter."-prefixed keys; the native store must read
    // them. Asserts the prefixed layout is read AND the old unprefixed layout is not
    // (so the bug that killed iOS background sync can't silently return).
    let suiteName = "lp.test.flutterPrefixed"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set("tok", forKey: "flutter.auth_session_token")
    defaults.set("user-1", forKey: "flutter.auth_backend_user_id")
    defaults.set("http://localhost:3000", forKey: "flutter.background_sync_backend_base_url")
    defaults.set(true, forKey: "flutter.health_authorized")

    let store = UserDefaultsBackgroundSyncStateStore(userDefaults: defaults)
    XCTAssertEqual(store.sessionToken, "tok")
    XCTAssertEqual(store.backendUserID, "user-1")
    XCTAssertEqual(store.backendBaseURL?.absoluteString, "http://localhost:3000")
    XCTAssertTrue(store.healthAuthorized)

    // Regression guard: the pre-fix unprefixed layout must NOT be readable.
    let suiteName2 = "lp.test.unprefixed"
    let defaults2 = UserDefaults(suiteName: suiteName2)!
    defaults2.removePersistentDomain(forName: suiteName2)
    defaults2.set("tok", forKey: "auth_session_token")
    let store2 = UserDefaultsBackgroundSyncStateStore(userDefaults: defaults2)
    XCTAssertNil(store2.sessionToken)
  }

  func testPerformSyncPostsStepsWhenStateIsAvailable() {
    let poster = MockPoster()
    let stepReader = MockStepReader(result: .success([
      BackgroundDailyStep(date: "2026-03-17", steps: 4100),
      BackgroundDailyStep(date: "2026-03-18", steps: 5200),
      BackgroundDailyStep(date: "2026-03-19", steps: 8765),
    ]))
    let syncNow = isoDate("2026-03-19T15:30:00Z")
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: MockStateStore(
        sessionToken: "session-token",
        backendBaseURL: URL(string: "http://127.0.0.1:3000"),
        healthAuthorized: true
      ),
      stepReader: stepReader,
      poster: poster,
      now: { syncNow }
    )

    let expectation = expectation(description: "sync completion")
    coordinator.performSync { result in
      XCTAssertEqual(result, .success)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
    XCTAssertEqual(poster.capturedToken, "session-token")
    XCTAssertEqual(poster.capturedURL?.absoluteString, "http://127.0.0.1:3000")
    // The sync window is derived locally now that `/challenges/current` is
    // gone; assert the reader still receives exactly that window.
    XCTAssertEqual(
      stepReader.capturedSyncDays,
      BackgroundStepSyncDateFormatter.localFallbackSyncDays(now: syncNow)
    )
    XCTAssertEqual(poster.v2Requests.count, 1)
    let payload = try! JSONSerialization.jsonObject(with: poster.v2Requests[0].body) as! [String: Any]
    XCTAssertEqual(payload["date"] as? String, "2026-03-19")
    XCTAssertEqual(payload["steps"] as? Int, 8765)
  }

  func testPerformSyncReturnsFailedWhenPostingFails() {
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: MockStateStore(
        sessionToken: "session-token",
        backendBaseURL: URL(string: "http://127.0.0.1:3000"),
        healthAuthorized: true
      ),
      stepReader: MockStepReader(result: .success([
        BackgroundDailyStep(date: "2026-03-19", steps: 8765)
      ])),
      poster: MockPoster(statusCode: 500),
      now: { isoDate("2026-03-19T15:30:00Z") }
    )

    let expectation = expectation(description: "sync completion")
    coordinator.performSync { result in
      XCTAssertEqual(result, .failed)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
  }

  func testPerformSyncUsesLocalTodayWindow() {
    let fallbackNow = isoDate("2026-03-19T15:30:00Z")
    let fallbackDate = BackgroundStepSyncDateFormatter.localDateString(now: fallbackNow)
    let poster = MockPoster()
    let stepReader = MockStepReader(result: .success([
      BackgroundDailyStep(date: fallbackDate, steps: 3200)
    ]))
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: MockStateStore(
        sessionToken: "session-token",
        backendBaseURL: URL(string: "http://127.0.0.1:3000"),
        healthAuthorized: true
      ),
      stepReader: stepReader,
      poster: poster,
      now: { fallbackNow }
    )

    let expectation = expectation(description: "sync completion")
    coordinator.performSync { result in
      XCTAssertEqual(result, .success)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
    XCTAssertEqual(poster.v2Requests.count, 1)
    let payload = try! JSONSerialization.jsonObject(with: poster.v2Requests[0].body) as! [String: Any]
    XCTAssertEqual(payload["date"] as? String, fallbackDate)
    XCTAssertEqual(payload["steps"] as? Int, 3200)
    XCTAssertEqual(stepReader.capturedSyncDays.count, 1)
    XCTAssertEqual(stepReader.capturedSyncDays.first?.date, fallbackDate)
    XCTAssertEqual(stepReader.capturedSyncDays.first?.startsAt, Calendar.current.startOfDay(for: fallbackNow))
    XCTAssertEqual(stepReader.capturedSyncDays.first?.endsAt, fallbackNow)
  }

  // Sub-hourly accounts must not let this native path claim the in-progress
  // hour (it uploads full-clock-hour rows that front-run the Dart fine sync
  // and smear live powerup-window scoring — 2026-07-24).
  func testHourlySamplesEndFloorsToHourStartOnSubHourlyAccounts() {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let midHour = isoDate("2026-03-19T15:37:12Z")

    XCTAssertEqual(
      BackgroundStepSyncCoordinator.hourlySamplesEnd(
        currentTime: midHour, bucketMinutes: 5, calendar: utc),
      isoDate("2026-03-19T15:00:00Z")
    )
    XCTAssertEqual(
      BackgroundStepSyncCoordinator.hourlySamplesEnd(
        currentTime: midHour, bucketMinutes: 30, calendar: utc),
      isoDate("2026-03-19T15:00:00Z")
    )
    // Every native account now excludes the open hour.
    XCTAssertEqual(
      BackgroundStepSyncCoordinator.hourlySamplesEnd(
        currentTime: midHour, bucketMinutes: 60, calendar: utc),
      isoDate("2026-03-19T15:00:00Z")
    )
  }

  func testHourlySamplesEndUsesNewYorkDSTGapAndRepeatedHourBoundaries() {
    var newYork = Calendar(identifier: .gregorian)
    newYork.timeZone = TimeZone(identifier: "America/New_York")!

    XCTAssertEqual(
      BackgroundStepSyncCoordinator.hourlySamplesEnd(
        currentTime: isoDate("2026-03-08T07:30:00Z"), bucketMinutes: 60,
        calendar: newYork
      ),
      isoDate("2026-03-08T07:00:00Z")
    )
    XCTAssertEqual(
      BackgroundStepSyncCoordinator.hourlySamplesEnd(
        currentTime: isoDate("2026-11-01T05:30:00Z"), bucketMinutes: 60,
        calendar: newYork
      ),
      isoDate("2026-11-01T05:00:00Z")
    )
    XCTAssertEqual(
      BackgroundStepSyncCoordinator.hourlySamplesEnd(
        currentTime: isoDate("2026-11-01T06:30:00Z"), bucketMinutes: 60,
        calendar: newYork
      ),
      isoDate("2026-11-01T06:00:00Z")
    )
  }

  func testPerformSyncExcludesOpenHourOnSubHourlyAccounts() {
    let poster = MockPoster()
    let stepReader = MockStepReader(result: .success([
      BackgroundDailyStep(date: "2026-03-19", steps: 8765)
    ]))
    let nowTime = isoDate("2026-03-19T15:30:00Z")
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: MockStateStore(
        sessionToken: "session-token",
        backendBaseURL: URL(string: "http://127.0.0.1:3000"),
        healthAuthorized: true,
        stepSampleBucketMinutes: 5
      ),
      stepReader: stepReader,
      poster: poster,
      now: { nowTime }
    )

    let expectation = expectation(description: "sync completion")
    coordinator.performSync { result in
      XCTAssertEqual(result, .success)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
    let range = stepReader.capturedHourlyRange
    XCTAssertNotNil(range)
    // End is the top of the current LOCAL hour — never `now` mid-hour.
    XCTAssertEqual(
      range?.to,
      Calendar.current.dateInterval(of: .hour, for: nowTime)?.start
    )
  }

  func testPerformSyncExcludesOpenHourOnHourlyAccounts() {
    let poster = MockPoster()
    let stepReader = MockStepReader(result: .success([
      BackgroundDailyStep(date: "2026-03-19", steps: 8765)
    ]))
    let nowTime = isoDate("2026-03-19T15:30:00Z")
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: MockStateStore(
        sessionToken: "session-token",
        backendBaseURL: URL(string: "http://127.0.0.1:3000"),
        healthAuthorized: true
      ),
      stepReader: stepReader,
      poster: poster,
      now: { nowTime }
    )

    let expectation = expectation(description: "sync completion")
    coordinator.performSync { result in
      XCTAssertEqual(result, .success)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
    XCTAssertEqual(
      stepReader.capturedHourlyRange?.to,
      Calendar.current.dateInterval(of: .hour, for: nowTime)?.start
    )
  }

  func testStepSyncRequestPayloadDetection() {
    XCTAssertTrue(
      BackgroundSyncPushPayload.isStepSyncRequest([
        "type": "STEP_SYNC_REQUEST"
      ])
    )
    XCTAssertFalse(
      BackgroundSyncPushPayload.isStepSyncRequest([
        "type": "CHALLENGE_INITIATED"
      ])
    )
  }
}

private func isoDate(_ value: String) -> Date {
  ISO8601DateFormatter().date(from: value)!
}

private func markerResponse() -> BackgroundStepHTTPResponse {
  BackgroundStepHTTPResponse(
    statusCode: 202,
    body: Data("{\"stepIntakeSemantics\":\"CANONICAL_SOURCE_QUEUE_V1\"}".utf8),
    error: nil
  )
}

private func waitUntil(
  timeout: TimeInterval = 1,
  condition: @escaping () -> Bool
) {
  let deadline = Date().addingTimeInterval(timeout)
  while !condition() && Date() < deadline {
    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
  }
}

private final class MockStateStore: BackgroundStepSyncStateStoring {
  var sessionToken: String?
  var backendUserID: String?
  var backendBaseURL: URL?
  var healthAuthorized: Bool
  var stepSampleBucketMinutes: Int = 60
  var pendingV2Envelope: String?
  var pendingLegacyEnvelope: String?
  var negativeCapability: String?

  init(
    sessionToken: String?,
    backendUserID: String? = "user-1",
    backendBaseURL: URL?,
    healthAuthorized: Bool,
    stepSampleBucketMinutes: Int = 60,
    pendingV2Envelope: String? = nil,
    pendingLegacyEnvelope: String? = nil,
    negativeCapability: String? = nil
  ) {
    self.sessionToken = sessionToken
    self.backendUserID = backendUserID
    self.backendBaseURL = backendBaseURL
    self.healthAuthorized = healthAuthorized
    self.stepSampleBucketMinutes = stepSampleBucketMinutes
    self.pendingV2Envelope = pendingV2Envelope
    self.pendingLegacyEnvelope = pendingLegacyEnvelope
    self.negativeCapability = negativeCapability
  }
}


private final class MockStepReader: StepReading {
  private let result: Result<[BackgroundDailyStep], Error>
  private let hourlyResult: Result<[[String: Any]], Error>
  var capturedSyncDays: [BackgroundSyncDay] = []
  var capturedHourlyRange: (from: Date, to: Date)?

  init(
    result: Result<[BackgroundDailyStep], Error>,
    hourlyResult: Result<[[String: Any]], Error> = .success([])
  ) {
    self.result = result
    self.hourlyResult = hourlyResult
  }

  func fetchStepCounts(
    for syncDays: [BackgroundSyncDay],
    completion: @escaping (Result<[BackgroundDailyStep], Error>) -> Void
  ) {
    capturedSyncDays = syncDays
    completion(result)
  }

  func fetchHourlyStepCounts(
    from startDate: Date,
    to endDate: Date,
    completion: @escaping (Result<[[String: Any]], Error>) -> Void
  ) {
    capturedHourlyRange = (from: startDate, to: endDate)
    completion(hourlyResult)
  }
}

private final class MockPoster: StepPosting {
  let statusCode: Int
  private var responses: [BackgroundStepHTTPResponse]
  private var legacyResponses: [BackgroundStepHTTPResponse]
  var capturedURL: URL?
  var capturedToken: String?
  var capturedPosts: [BackgroundDailyStep] = []
  var samplePostCount = 0
  var v2Requests: [BackgroundStepSyncV2Request] = []
  var legacyRequests: [BackgroundStepLegacyRequest] = []

  init(
    statusCode: Int = 200,
    responses: [BackgroundStepHTTPResponse] = [],
    legacyResponses: [BackgroundStepHTTPResponse] = []
  ) {
    self.statusCode = statusCode
    self.responses = responses
    self.legacyResponses = legacyResponses
  }

  func postSyncV2(
    _ request: BackgroundStepSyncV2Request,
    completion: @escaping (BackgroundStepHTTPResponse) -> Void
  ) {
    v2Requests.append(request)
    capturedURL = request.baseURL
    capturedToken = request.sessionToken
    if responses.isEmpty {
      if statusCode == 200 {
        completion(BackgroundStepHTTPResponse(
          statusCode: 202,
          body: Data("{\"stepIntakeSemantics\":\"CANONICAL_SOURCE_QUEUE_V1\"}".utf8),
          error: nil
        ))
      } else {
        completion(BackgroundStepHTTPResponse(statusCode: statusCode, body: Data("{}".utf8), error: nil))
      }
    } else {
      completion(responses.removeFirst())
    }
  }

  func postLegacy(
    _ request: BackgroundStepLegacyRequest,
    completion: @escaping (BackgroundStepHTTPResponse) -> Void
  ) {
    legacyRequests.append(request)
    capturedURL = request.baseURL
    capturedToken = request.sessionToken
    if request.path == "/steps",
       let payload = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
       let date = payload["date"] as? String,
       let steps = payload["steps"] as? Int {
      capturedPosts.append(BackgroundDailyStep(date: date, steps: steps))
    } else if request.path == "/steps/samples" {
      samplePostCount += 1
    }
    if legacyResponses.isEmpty {
      completion(BackgroundStepHTTPResponse(statusCode: statusCode, body: Data("{}".utf8), error: nil))
    } else {
      completion(legacyResponses.removeFirst())
    }
  }

  func postSteps(
    baseURL: URL,
    sessionToken: String,
    steps: Int,
    date: String,
    completion: @escaping (Int?, Error?) -> Void
  ) {
    capturedURL = baseURL
    capturedToken = sessionToken
    capturedPosts.append(BackgroundDailyStep(date: date, steps: steps))
    completion(statusCode, nil)
  }

  func postStepSamples(
    baseURL: URL,
    sessionToken: String,
    samples: [[String: Any]],
    completion: @escaping (Int?, Error?) -> Void
  ) {
    samplePostCount += 1
    completion(statusCode, nil)
  }
}

private enum TestError: Error {
  case failed
}

private final class DeferredPoster: StepPosting {
  var v2Requests: [BackgroundStepSyncV2Request] = []
  var legacyRequests: [BackgroundStepLegacyRequest] = []
  private var completions: [(BackgroundStepHTTPResponse) -> Void] = []

  func postSyncV2(
    _ request: BackgroundStepSyncV2Request,
    completion: @escaping (BackgroundStepHTTPResponse) -> Void
  ) {
    v2Requests.append(request)
    completions.append(completion)
  }

  func completeNextWithMarker() {
    completeNext(BackgroundStepHTTPResponse(
      statusCode: 202,
      body: Data("{\"stepIntakeSemantics\":\"CANONICAL_SOURCE_QUEUE_V1\"}".utf8),
      error: nil
    ))
  }

  func completeNext(_ response: BackgroundStepHTTPResponse) {
    let completion = completions.removeFirst()
    completion(response)
  }

  func postLegacy(
    _ request: BackgroundStepLegacyRequest,
    completion: @escaping (BackgroundStepHTTPResponse) -> Void
  ) {
    legacyRequests.append(request)
    completion(BackgroundStepHTTPResponse(statusCode: 200, body: Data("{}".utf8), error: nil))
  }

  func postSteps(
    baseURL: URL,
    sessionToken: String,
    steps: Int,
    date: String,
    completion: @escaping (Int?, Error?) -> Void
  ) { completion(200, nil) }

  func postStepSamples(
    baseURL: URL,
    sessionToken: String,
    samples: [[String: Any]],
    completion: @escaping (Int?, Error?) -> Void
  ) { completion(200, nil) }
}
