import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testPerformSyncReturnsNoDataWhenSessionTokenIsMissing() {
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: MockStateStore(
        sessionToken: nil,
        backendBaseURL: URL(string: "http://127.0.0.1:3000"),
        healthAuthorized: true
      ),
      challengeSyncDaysFetcher: MockChallengeSyncDaysFetcher(syncDays: [
        BackgroundSyncDay(
          date: "2026-03-19",
          startsAt: isoDate("2026-03-19T04:00:00Z"),
          endsAt: isoDate("2026-03-19T15:30:00Z")
        )
      ]),
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

  func testPerformSyncPostsStepsWhenStateIsAvailable() {
    let poster = MockPoster()
    let stepReader = MockStepReader(result: .success([
      BackgroundDailyStep(date: "2026-03-17", steps: 4100),
      BackgroundDailyStep(date: "2026-03-18", steps: 5200),
      BackgroundDailyStep(date: "2026-03-19", steps: 8765),
    ]))
    let syncDays = [
      BackgroundSyncDay(
        date: "2026-03-17",
        startsAt: isoDate("2026-03-17T04:00:00Z"),
        endsAt: isoDate("2026-03-18T04:00:00Z")
      ),
      BackgroundSyncDay(
        date: "2026-03-18",
        startsAt: isoDate("2026-03-18T04:00:00Z"),
        endsAt: isoDate("2026-03-19T04:00:00Z")
      ),
      BackgroundSyncDay(
        date: "2026-03-19",
        startsAt: isoDate("2026-03-19T04:00:00Z"),
        endsAt: isoDate("2026-03-19T15:30:00Z")
      ),
    ]
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: MockStateStore(
        sessionToken: "session-token",
        backendBaseURL: URL(string: "http://127.0.0.1:3000"),
        healthAuthorized: true
      ),
      challengeSyncDaysFetcher: MockChallengeSyncDaysFetcher(syncDays: syncDays),
      stepReader: stepReader,
      poster: poster,
      now: { isoDate("2026-03-19T15:30:00Z") }
    )

    let expectation = expectation(description: "sync completion")
    coordinator.performSync { result in
      XCTAssertEqual(result, .success)
      expectation.fulfill()
    }

    wait(for: [expectation], timeout: 1)
    XCTAssertEqual(poster.capturedToken, "session-token")
    XCTAssertEqual(poster.capturedURL?.absoluteString, "http://127.0.0.1:3000")
    XCTAssertEqual(stepReader.capturedSyncDays, syncDays)
    XCTAssertEqual(
      poster.capturedPosts,
      [
        BackgroundDailyStep(date: "2026-03-17", steps: 4100),
        BackgroundDailyStep(date: "2026-03-18", steps: 5200),
        BackgroundDailyStep(date: "2026-03-19", steps: 8765),
      ]
    )
  }

  func testPerformSyncReturnsFailedWhenPostingFails() {
    let coordinator = BackgroundStepSyncCoordinator(
      stateStore: MockStateStore(
        sessionToken: "session-token",
        backendBaseURL: URL(string: "http://127.0.0.1:3000"),
        healthAuthorized: true
      ),
      challengeSyncDaysFetcher: MockChallengeSyncDaysFetcher(syncDays: [
        BackgroundSyncDay(
          date: "2026-03-19",
          startsAt: isoDate("2026-03-19T04:00:00Z"),
          endsAt: isoDate("2026-03-19T15:30:00Z")
        )
      ]),
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

  func testPerformSyncFallsBackToLocalTodayWhenNoChallengeSyncDaysAreAvailable() {
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
      challengeSyncDaysFetcher: MockChallengeSyncDaysFetcher(syncDays: nil),
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
    XCTAssertEqual(
      poster.capturedPosts,
      [BackgroundDailyStep(date: fallbackDate, steps: 3200)]
    )
    XCTAssertEqual(stepReader.capturedSyncDays.count, 1)
    XCTAssertEqual(stepReader.capturedSyncDays.first?.date, fallbackDate)
    XCTAssertEqual(stepReader.capturedSyncDays.first?.startsAt, Calendar.current.startOfDay(for: fallbackNow))
    XCTAssertEqual(stepReader.capturedSyncDays.first?.endsAt, fallbackNow)
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

private struct MockStateStore: BackgroundStepSyncStateStoring {
  let sessionToken: String?
  let backendBaseURL: URL?
  let healthAuthorized: Bool
}

private final class MockChallengeSyncDaysFetcher: ChallengeSyncDaysFetching {
  let syncDays: [BackgroundSyncDay]?

  init(syncDays: [BackgroundSyncDay]?) {
    self.syncDays = syncDays
  }

  func fetchCurrentChallengeSyncDays(
    baseURL: URL,
    sessionToken: String,
    completion: @escaping ([BackgroundSyncDay]?) -> Void
  ) {
    completion(syncDays)
  }
}

private final class MockStepReader: StepReading {
  private let result: Result<[BackgroundDailyStep], Error>
  var capturedSyncDays: [BackgroundSyncDay] = []

  init(result: Result<[BackgroundDailyStep], Error>) {
    self.result = result
  }

  func fetchStepCounts(
    for syncDays: [BackgroundSyncDay],
    completion: @escaping (Result<[BackgroundDailyStep], Error>) -> Void
  ) {
    capturedSyncDays = syncDays
    completion(result)
  }
}

private final class MockPoster: StepPosting {
  let statusCode: Int
  var capturedURL: URL?
  var capturedToken: String?
  var capturedPosts: [BackgroundDailyStep] = []

  init(statusCode: Int = 200) {
    self.statusCode = statusCode
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
}
