import BackgroundTasks
import Flutter
import HealthKit
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var notificationChannel: FlutterMethodChannel?
  private var backgroundSyncChannel: FlutterMethodChannel?
  private let healthStore = HKHealthStore()
  private var hasRegisteredHealthObserver = false
  private lazy var backgroundSyncCoordinator = BackgroundStepSyncCoordinator(
    stateStore: UserDefaultsBackgroundSyncStateStore(),
    challengeSyncDaysFetcher: URLSessionChallengeSyncDaysFetcher(),
    stepReader: HealthKitStepReader(),
    poster: URLSessionStepPoster()
  )

  private var backgroundRefreshTaskIdentifier: String {
    let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.steptracker.app"
    return "\(bundleIdentifier).periodicStepSync"
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window!.rootViewController as! FlutterViewController

    notificationChannel = FlutterMethodChannel(
      name: "com.steptracker/notifications",
      binaryMessenger: controller.binaryMessenger
    )

    notificationChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "requestPermission" {
        self?.requestNotificationPermission(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    backgroundSyncChannel = FlutterMethodChannel(
      name: "com.steptracker/background_sync",
      binaryMessenger: controller.binaryMessenger
    )

    backgroundSyncChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "unavailable",
            message: "AppDelegate deallocated",
            details: nil
          )
        )
        return
      }

      if call.method == "enableHealthKitBackgroundDelivery" {
        self.enableHealthKitBackgroundDelivery()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    registerBackgroundRefreshTask()
    scheduleBackgroundRefresh()
    enableHealthKitBackgroundDelivery()

    UNUserNotificationCenter.current().delegate = self

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func requestNotificationPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound]
    ) { granted, _ in
      DispatchQueue.main.async {
        if granted {
          UIApplication.shared.registerForRemoteNotifications()
        }
        result(granted)
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    notificationChannel?.invokeMethod("onDeviceToken", arguments: token)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("Failed to register for remote notifications: \(error.localizedDescription)")
  }

  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    guard BackgroundSyncPushPayload.isStepSyncRequest(userInfo) else {
      completionHandler(.noData)
      return
    }

    backgroundSyncCoordinator.performSync { result in
      completionHandler(result.fetchResult)
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    var payload: [String: Any] = [:]
    for (key, value) in userInfo {
      if let stringKey = key as? String {
        payload[stringKey] = value
      }
    }
    notificationChannel?.invokeMethod("onNotificationTap", arguments: payload)
    completionHandler()
  }

  private func registerBackgroundRefreshTask() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: backgroundRefreshTaskIdentifier,
      using: nil
    ) { [weak self] task in
      guard
        let self,
        let appRefreshTask = task as? BGAppRefreshTask
      else {
        task.setTaskCompleted(success: false)
        return
      }

      self.handleBackgroundRefresh(task: appRefreshTask)
    }
  }

  private func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: backgroundRefreshTaskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)

    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      print("Failed to schedule BGAppRefreshTask: \(error.localizedDescription)")
    }
  }

  private func handleBackgroundRefresh(task: BGAppRefreshTask) {
    scheduleBackgroundRefresh()

    var finished = false

    func finish(_ result: BackgroundStepSyncResult) {
      guard !finished else { return }
      finished = true
      task.setTaskCompleted(success: result != .failed)
    }

    task.expirationHandler = {
      finish(.failed)
    }

    backgroundSyncCoordinator.performSync { result in
      finish(result)
    }
  }

  private func enableHealthKitBackgroundDelivery() {
    guard HKHealthStore.isHealthDataAvailable() else { return }
    registerHealthKitObserverIfNeeded()

    guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
      return
    }

    healthStore.enableBackgroundDelivery(
      for: stepType,
      frequency: .immediate
    ) { success, error in
      if let error {
        print("Failed to enable HealthKit background delivery: \(error.localizedDescription)")
        return
      }

      if !success {
        print("HealthKit background delivery was not enabled")
      }
    }
  }

  private func registerHealthKitObserverIfNeeded() {
    guard !hasRegisteredHealthObserver else { return }
    guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
      return
    }

    hasRegisteredHealthObserver = true

    let query = HKObserverQuery(sampleType: stepType, predicate: nil) { [weak self] _, completionHandler, error in
      if let error {
        print("HealthKit observer error: \(error.localizedDescription)")
        completionHandler()
        return
      }

      self?.backgroundSyncCoordinator.performSync { _ in
        completionHandler()
      }
    }

    healthStore.execute(query)
  }
}

enum BackgroundStepSyncResult: Equatable {
  case success
  case noData
  case failed

  var fetchResult: UIBackgroundFetchResult {
    switch self {
    case .success:
      return .newData
    case .noData:
      return .noData
    case .failed:
      return .failed
    }
  }
}

protocol BackgroundStepSyncStateStoring {
  var sessionToken: String? { get }
  var backendBaseURL: URL? { get }
  var healthAuthorized: Bool { get }
}

protocol ChallengeSyncDaysFetching {
  func fetchCurrentChallengeSyncDays(
    baseURL: URL,
    sessionToken: String,
    completion: @escaping ([BackgroundSyncDay]?) -> Void
  )
}

struct BackgroundSyncDay: Equatable {
  let date: String
  let startsAt: Date
  let endsAt: Date
}

struct BackgroundDailyStep: Equatable {
  let date: String
  let steps: Int
}

protocol StepReading {
  func fetchStepCounts(
    for syncDays: [BackgroundSyncDay],
    completion: @escaping (Result<[BackgroundDailyStep], Error>) -> Void
  )
  func fetchHourlyStepCounts(
    from startDate: Date,
    to endDate: Date,
    completion: @escaping (Result<[[String: Any]], Error>) -> Void
  )
}

protocol StepPosting {
  func postSteps(
    baseURL: URL,
    sessionToken: String,
    steps: Int,
    date: String,
    completion: @escaping (Int?, Error?) -> Void
  )
  func postStepSamples(
    baseURL: URL,
    sessionToken: String,
    samples: [[String: Any]],
    completion: @escaping (Int?, Error?) -> Void
  )
}

final class BackgroundStepSyncCoordinator {
  private let stateStore: BackgroundStepSyncStateStoring
  private let challengeSyncDaysFetcher: ChallengeSyncDaysFetching
  private let stepReader: StepReading
  private let poster: StepPosting
  private let now: () -> Date

  init(
    stateStore: BackgroundStepSyncStateStoring,
    challengeSyncDaysFetcher: ChallengeSyncDaysFetching,
    stepReader: StepReading,
    poster: StepPosting,
    now: @escaping () -> Date = Date.init
  ) {
    self.stateStore = stateStore
    self.challengeSyncDaysFetcher = challengeSyncDaysFetcher
    self.stepReader = stepReader
    self.poster = poster
    self.now = now
  }

  func performSync(completion: @escaping (BackgroundStepSyncResult) -> Void) {
    guard
      let sessionToken = stateStore.sessionToken,
      !sessionToken.isEmpty,
      stateStore.healthAuthorized,
      let backendBaseURL = stateStore.backendBaseURL
    else {
      completion(.noData)
      return
    }

    let currentTime = now()

    challengeSyncDaysFetcher.fetchCurrentChallengeSyncDays(
      baseURL: backendBaseURL,
      sessionToken: sessionToken
    ) { [stepReader, poster] syncDays in
      let resolvedSyncDays =
        (syncDays?.isEmpty == false)
        ? syncDays!
        : BackgroundStepSyncDateFormatter.localFallbackSyncDays(now: currentTime)

      stepReader.fetchStepCounts(for: resolvedSyncDays) { [stepReader] result in
        switch result {
        case .failure:
          completion(.failed)
        case .success(let dailySteps):
          guard !dailySteps.isEmpty else {
            completion(.noData)
            return
          }

          Self.postDailySteps(
            dailySteps,
            baseURL: backendBaseURL,
            sessionToken: sessionToken,
            poster: poster
          ) { dailyResult in
            guard dailyResult == .success else {
              completion(dailyResult)
              return
            }

            // After daily sync succeeds, sync hourly samples for today
            let todayStart = Calendar.current.startOfDay(for: currentTime)
            stepReader.fetchHourlyStepCounts(from: todayStart, to: currentTime) { hourlyResult in
              switch hourlyResult {
              case .failure:
                // Don't fail the overall sync if hourly samples fail
                completion(.success)
              case .success(let samples):
                guard !samples.isEmpty else {
                  completion(.success)
                  return
                }
                poster.postStepSamples(
                  baseURL: backendBaseURL,
                  sessionToken: sessionToken,
                  samples: samples
                ) { _, _ in
                  // Ignore hourly post failures - daily sync already succeeded
                  completion(.success)
                }
              }
            }
          }
        }
      }
    }
  }

  private static func postDailySteps(
    _ dailySteps: [BackgroundDailyStep],
    baseURL: URL,
    sessionToken: String,
    poster: StepPosting,
    completion: @escaping (BackgroundStepSyncResult) -> Void
  ) {
    func postNext(index: Int) {
      guard index < dailySteps.count else {
        completion(.success)
        return
      }

      let entry = dailySteps[index]

      poster.postSteps(
        baseURL: baseURL,
        sessionToken: sessionToken,
        steps: entry.steps,
        date: entry.date
      ) { statusCode, error in
        if error != nil {
          completion(.failed)
          return
        }

        guard let statusCode else {
          completion(.failed)
          return
        }

        if statusCode == 401 {
          completion(.noData)
          return
        }

        if !(200..<300).contains(statusCode) {
          completion(.failed)
          return
        }

        postNext(index: index + 1)
      }
    }

    postNext(index: 0)
  }
}

struct BackgroundSyncPushPayload {
  static func isStepSyncRequest(_ userInfo: [AnyHashable: Any]) -> Bool {
    guard let type = userInfo["type"] as? String else {
      return false
    }

    return type == "STEP_SYNC_REQUEST"
  }
}

struct BackgroundStepSyncDateFormatter {
  static func localDateString(now: Date = Date()) -> String {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .day], from: now)
    let year = components.year ?? 0
    let month = components.month ?? 0
    let day = components.day ?? 0

    return "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))"
  }

  static func localFallbackSyncDays(now: Date = Date()) -> [BackgroundSyncDay] {
    [
      BackgroundSyncDay(
        date: localDateString(now: now),
        startsAt: Calendar.current.startOfDay(for: now),
        endsAt: now
      )
    ]
  }
}

final class UserDefaultsBackgroundSyncStateStore: BackgroundStepSyncStateStoring {
  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
  }

  var sessionToken: String? {
    userDefaults.string(forKey: "auth_session_token")
  }

  var backendBaseURL: URL? {
    guard
      let rawValue = userDefaults.string(forKey: BackgroundSyncBootstrapKeys.backendBaseURL)
    else {
      return nil
    }

    return URL(string: rawValue)
  }

  var healthAuthorized: Bool {
    userDefaults.bool(forKey: "health_authorized")
  }
}

struct BackgroundSyncBootstrapKeys {
  static let backendBaseURL = "background_sync_backend_base_url"
}

final class URLSessionChallengeSyncDaysFetcher: ChallengeSyncDaysFetching {
  private let session: URLSession
  private let iso8601Formatter = ISO8601DateFormatter()

  init(session: URLSession = .shared) {
    self.session = session
    iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  }

  func fetchCurrentChallengeSyncDays(
    baseURL: URL,
    sessionToken: String,
    completion: @escaping ([BackgroundSyncDay]?) -> Void
  ) {
    guard let url = URL(string: "/challenges/current", relativeTo: baseURL)?.absoluteURL else {
      completion(nil)
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")

    session.dataTask(with: request) { data, response, _ in
      guard
        let statusCode = (response as? HTTPURLResponse)?.statusCode,
        (200..<300).contains(statusCode),
        let data,
        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else {
        completion(nil)
        return
      }

      completion(self.parseSyncDays(from: payload))
    }.resume()
  }

  private func parseSyncDays(from payload: [String: Any]) -> [BackgroundSyncDay]? {
    guard let rawSyncDays = payload["syncDays"] as? [[String: Any]] else {
      return nil
    }

    let parsedSyncDays: [BackgroundSyncDay] = rawSyncDays.compactMap { entry -> BackgroundSyncDay? in
      guard
        let date = entry["date"] as? String,
        let startsAtValue = entry["startsAt"] as? String,
        let endsAtValue = entry["endsAt"] as? String,
        let startsAt = iso8601Formatter.date(from: startsAtValue),
        let endsAt = iso8601Formatter.date(from: endsAtValue),
        endsAt > startsAt
      else {
        return nil
      }

      return BackgroundSyncDay(
        date: date,
        startsAt: startsAt,
        endsAt: endsAt
      )
    }

    return parsedSyncDays.count == rawSyncDays.count ? parsedSyncDays : nil
  }
}

final class HealthKitStepReader: StepReading {
  private let healthStore: HKHealthStore

  init(healthStore: HKHealthStore = HKHealthStore()) {
    self.healthStore = healthStore
  }

  func fetchStepCounts(
    for syncDays: [BackgroundSyncDay],
    completion: @escaping (Result<[BackgroundDailyStep], Error>) -> Void
  ) {
    guard HKHealthStore.isHealthDataAvailable() else {
      completion(.success([]))
      return
    }

    guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
      completion(.success([]))
      return
    }

    guard !syncDays.isEmpty else {
      completion(.success([]))
      return
    }

    var currentIndex = 0
    var entries: [BackgroundDailyStep] = []

    func fetchNextDay() {
      guard currentIndex < syncDays.count else {
        completion(.success(entries))
        return
      }

      let syncDay = syncDays[currentIndex]
      let predicate = HKQuery.predicateForSamples(
        withStart: syncDay.startsAt,
        end: syncDay.endsAt,
        options: .strictStartDate
      )

      let query = HKStatisticsQuery(
        quantityType: stepType,
        quantitySamplePredicate: predicate,
        options: .cumulativeSum
      ) { _, statistics, error in
        if let error {
          completion(.failure(error))
          return
        }

        let steps = Int(
          statistics?.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0
        )
        entries.append(
          BackgroundDailyStep(
            date: syncDay.date,
            steps: steps
          )
        )

        currentIndex += 1
        fetchNextDay()
      }

      healthStore.execute(query)
    }

    fetchNextDay()
  }

  func fetchHourlyStepCounts(
    from startDate: Date,
    to endDate: Date,
    completion: @escaping (Result<[[String: Any]], Error>) -> Void
  ) {
    guard HKHealthStore.isHealthDataAvailable() else {
      completion(.success([]))
      return
    }

    guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
      completion(.success([]))
      return
    }

    let calendar = Calendar.current
    let anchorDate = calendar.startOfDay(for: startDate)
    let interval = DateComponents(hour: 1)

    let predicate = HKQuery.predicateForSamples(
      withStart: startDate,
      end: endDate,
      options: .strictStartDate
    )

    let query = HKStatisticsCollectionQuery(
      quantityType: stepType,
      quantitySamplePredicate: predicate,
      options: .cumulativeSum,
      anchorDate: anchorDate,
      intervalComponents: interval
    )

    query.initialResultsHandler = { _, results, error in
      if let error {
        completion(.failure(error))
        return
      }

      guard let results else {
        completion(.success([]))
        return
      }

      let formatter = ISO8601DateFormatter()
      var samples: [[String: Any]] = []

      results.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
        let steps = Int(statistics.sumQuantity()?.doubleValue(for: HKUnit.count()) ?? 0)
        if steps > 0 {
          samples.append([
            "periodStart": formatter.string(from: statistics.startDate),
            "periodEnd": formatter.string(from: statistics.endDate),
            "steps": steps,
          ])
        }
      }

      completion(.success(samples))
    }

    healthStore.execute(query)
  }
}

final class URLSessionStepPoster: StepPosting {
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func postSteps(
    baseURL: URL,
    sessionToken: String,
    steps: Int,
    date: String,
    completion: @escaping (Int?, Error?) -> Void
  ) {
    guard let url = URL(string: "/steps", relativeTo: baseURL)?.absoluteURL else {
      completion(nil, NSError(domain: "BackgroundStepSync", code: -1))
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: [
        "steps": steps,
        "date": date,
      ])
    } catch {
      completion(nil, error)
      return
    }

    session.dataTask(with: request) { _, response, error in
      let statusCode = (response as? HTTPURLResponse)?.statusCode
      completion(statusCode, error)
    }.resume()
  }

  func postStepSamples(
    baseURL: URL,
    sessionToken: String,
    samples: [[String: Any]],
    completion: @escaping (Int?, Error?) -> Void
  ) {
    guard let url = URL(string: "/steps/samples", relativeTo: baseURL)?.absoluteURL else {
      completion(nil, NSError(domain: "BackgroundStepSync", code: -1))
      return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")

    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: [
        "samples": samples,
      ])
    } catch {
      completion(nil, error)
      return
    }

    session.dataTask(with: request) { _, response, error in
      let statusCode = (response as? HTTPURLResponse)?.statusCode
      completion(statusCode, error)
    }.resume()
  }
}
