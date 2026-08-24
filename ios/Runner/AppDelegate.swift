import BackgroundTasks
import FBAudienceNetwork
import Flutter
import HealthKit
import UIKit
import UserNotifications
import google_mobile_ads

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var notificationChannel: FlutterMethodChannel?
  private var backgroundSyncChannel: FlutterMethodChannel?
  private var appInfoChannel: FlutterMethodChannel?
  private var referralChannel: FlutterMethodChannel?
  private var metaAdsChannel: FlutterMethodChannel?
  private let healthStore = HKHealthStore()
  private var hasRegisteredHealthObserver = false
  private lazy var backgroundSyncCoordinator = BackgroundStepSyncCoordinator(
    stateStore: UserDefaultsBackgroundSyncStateStore(),
    stepReader: HealthKitStepReader(),
    poster: URLSessionStepPoster(),
    hasExecutionBudget: {
      let remaining = UIApplication.shared.backgroundTimeRemaining
      return remaining == .greatestFiniteMagnitude || remaining > 20
    }
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

    // Custom native-ad layout for the races-tab in-feed ad (AdInlineCard
    // requests factoryId "raceFeedAd"). Registered for the app's lifetime —
    // no unregister needed.
    FLTGoogleMobileAdsPlugin.registerNativeAdFactory(
      self,
      factoryId: "raceFeedAd",
      nativeAdFactory: RaceFeedNativeAdFactory()
    )

    let controller = window!.rootViewController as! FlutterViewController

    // Meta requires its advertiser-tracking flag to be set from the app's ATT
    // result before Google Mobile Ads initializes. Dart owns the ATT prompt, so
    // this small bridge forwards that result to the native Meta SDK.
    metaAdsChannel = FlutterMethodChannel(
      name: "com.steptracker/meta_ads",
      binaryMessenger: controller.binaryMessenger
    )
    metaAdsChannel?.setMethodCallHandler { call, result in
      guard call.method == "setAdvertiserTrackingEnabled" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let enabled = call.arguments as? Bool else {
        result(
          FlutterError(
            code: "invalid_argument",
            message: "Expected a boolean advertiser-tracking value.",
            details: nil
          )
        )
        return
      }
      FBAdSettings.setAdvertiserTrackingEnabled(enabled)
      result(nil)
    }

    notificationChannel = FlutterMethodChannel(
      name: "com.steptracker/notifications",
      binaryMessenger: controller.binaryMessenger
    )

    notificationChannel?.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "requestPermission":
        self?.requestNotificationPermission(result: result)
      case "getPermissionStatus":
        self?.getNotificationPermissionStatus(result: result)
      case "registerForRemoteNotifications":
        self?.registerForRemoteNotificationsIfAuthorized(result: result)
      default:
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

    appInfoChannel = FlutterMethodChannel(
      name: "com.steptracker/app_info",
      binaryMessenger: controller.binaryMessenger
    )

    appInfoChannel?.setMethodCallHandler { call, result in
      if call.method == "isTestFlight" {
        result(AppDelegate.isTestFlightBuild())
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Referral clipboard handoff (iOS deferred-attribution convenience).
    //  * clipboardHasProbableUrl — UIPasteboard.detectPatterns runs SILENTLY
    //    (no "Allow Paste?" prompt) and only reports whether a URL is present.
    //  * readClipboardUrl — actually reads the URL string; invoked ONLY behind a
    //    user tap (so the read is consented), after detect says one exists.
    // The prompt-free one-tap upgrade is a UIPasteControl button (iOS 16+); this
    // detect-then-tap split is the equivalent without a custom platform view.
    referralChannel = FlutterMethodChannel(
      name: "com.steptracker/referral",
      binaryMessenger: controller.binaryMessenger
    )

    referralChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "clipboardHasProbableUrl":
        if #available(iOS 14.0, *) {
          UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { outcome in
            DispatchQueue.main.async {
              switch outcome {
              case .success(let patterns):
                result(patterns.contains(.probableWebURL))
              case .failure:
                result(false)
              }
            }
          }
        } else {
          result(false)
        }
      case "readClipboardUrl":
        // Returns a MAP, not a bare string, so Dart can tell "the read gave us
        // nothing" apart from "nothing was ever detected". Those two produced
        // an identical nil before, which is why years of silent referral loss
        // could never be attributed to a stage. Classification only — the read
        // itself is unchanged.
        //
        // On iOS 16+ an unconsented read raises the "Allow Paste?" alert and a
        // denial surfaces here as nil url AND nil string, which — given the
        // caller only asks after detectPatterns said a URL IS present — is the
        // denial signature.
        let pasteboard = UIPasteboard.general
        if let url = pasteboard.url {
          result(["status": "ok", "value": url.absoluteString])
        } else if let string = pasteboard.string {
          result(["status": "ok", "value": string])
        } else {
          result(["status": "denied"])
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    registerBackgroundRefreshTask()
    scheduleBackgroundRefresh()
    // Fix C4: do NOT register HealthKit background delivery here — this runs before
    // the user has granted Health access, so the observer registration is wasted/
    // ignored. The real registration happens via the "enableHealthKitBackgroundDelivery"
    // method channel (above), which Dart invokes right after a confirmed Health-auth
    // grant (main_shell.dart restoreHealthAuthState path) on every launch.

    UNUserNotificationCenter.current().delegate = self

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Whether this binary is running as a TestFlight (or local dev) build rather
  // than a public App Store install. TestFlight and dev builds carry a *sandbox*
  // App Store receipt; App Store installs carry a *production* one. This is a
  // runtime check, so the SAME binary correctly reports `true` in TestFlight and
  // `false` once it's promoted to the App Store — no separate build needed.
  static func isTestFlightBuild() -> Bool {
    #if DEBUG
    return true
    #else
    guard let receiptURL = Bundle.main.appStoreReceiptURL else { return false }
    return receiptURL.lastPathComponent == "sandboxReceipt"
    #endif
  }

  /// The REAL permission state, so Dart never has to trust a cached flag.
  private func getNotificationPermissionStatus(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let status: String
      switch settings.authorizationStatus {
      case .authorized: status = "authorized"
      case .provisional: status = "provisional"
      case .ephemeral: status = "ephemeral"
      case .denied: status = "denied"
      case .notDetermined: status = "notDetermined"
      @unknown default: status = "notDetermined"
      }
      DispatchQueue.main.async { result(status) }
    }
  }

  /// Re-registers with APNs WITHOUT prompting — tokens rotate across
  /// reinstall/restore/new-device, so this must run every session for users
  /// who already granted permission. Returns whether registration was kicked
  /// off (the token itself arrives async via didRegisterForRemoteNotifications).
  private func registerForRemoteNotificationsIfAuthorized(
    result: @escaping FlutterResult
  ) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      DispatchQueue.main.async {
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
          UIApplication.shared.registerForRemoteNotifications()
          result(true)
        default:
          result(false)
        }
      }
    }
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
    // Forward to Dart: without this, an APNs registration failure is invisible
    // — the user thinks notifications are on while the backend keeps pushing
    // to stale tokens.
    notificationChannel?.invokeMethod(
      "onDeviceTokenError",
      arguments: error.localizedDescription
    )
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
    let completionGate = BackgroundTaskCompletionGate()

    func finish(_ result: BackgroundStepSyncResult) {
      completionGate.finish(result != .failed) { success in
        task.setTaskCompleted(success: success)
      }
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

final class BackgroundTaskCompletionGate {
  private let lock = NSLock()
  private var finished = false

  func finish(_ value: Bool, completion: (Bool) -> Void) {
    lock.lock()
    guard !finished else {
      lock.unlock()
      return
    }
    finished = true
    lock.unlock()
    completion(value)
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

protocol BackgroundStepSyncStateStoring: AnyObject {
  var sessionToken: String? { get }
  var backendUserID: String? { get }
  var backendBaseURL: URL? { get }
  var healthAuthorized: Bool { get }
  var stepSampleBucketMinutes: Int { get }
  var pendingV2Envelope: String? { get set }
  var pendingLegacyEnvelope: String? { get set }
  var negativeCapability: String? { get set }
}

// Default keeps every existing conformer (and shipped behavior) on hourly;
// only the real store opts accounts into the sub-hourly gating below.
extension BackgroundStepSyncStateStoring {
  var stepSampleBucketMinutes: Int { 60 }
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
  func postSyncV2(
    _ request: BackgroundStepSyncV2Request,
    completion: @escaping (BackgroundStepHTTPResponse) -> Void
  )
  func postLegacy(
    _ request: BackgroundStepLegacyRequest,
    completion: @escaping (BackgroundStepHTTPResponse) -> Void
  )
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

struct BackgroundStepHTTPResponse {
  let statusCode: Int?
  let body: Data?
  let error: Error?
}

private enum BackgroundStepPostResult {
  case response(BackgroundStepHTTPResponse)
  case sessionChanged
}

struct BackgroundStepSyncV2Request: Equatable {
  let baseURL: URL
  let sessionToken: String
  let idempotencyKey: String
  let timeZone: String
  let appVersion: String?
  let body: Data
}

struct BackgroundStepLegacyRequest: Equatable {
  let baseURL: URL
  let path: String
  let sessionToken: String
  let timeZone: String
  let body: Data
}

private struct BackgroundStepSyncV2Envelope: Codable {
  let ownerID: String
  let backendBaseURL: String
  let idempotencyKey: String
  let timeZone: String
  let body: Data
  let createdAt: Date
}

private struct BackgroundStepSyncLegacyEnvelope: Codable {
  let ownerID: String
  let backendBaseURL: String
  let timeZone: String
  let dailyBody: Data
  let samplesBody: Data
  var dailyComplete: Bool
  var samplesComplete: Bool
}

private struct BackgroundStepSyncNegativeCapability: Codable {
  let ownerID: String
  let backendBaseURL: String
  let unsupportedUntil: Date
}

private struct BackgroundStepSyncSession {
  let token: String
  let ownerID: String
  let baseURL: URL
}

final class BackgroundStepSyncCoordinator {
  private let stateStore: BackgroundStepSyncStateStoring
  private let stepReader: StepReading
  private let poster: StepPosting
  private let now: () -> Date
  private let timeZoneIdentifier: () -> String
  private let appVersion: () -> String?
  private let newIdempotencyKey: () -> String
  private let hasExecutionBudget: () -> Bool
  private let gate = DispatchQueue(label: "com.steptracker.background-step-sync")
  private var isRunning = false
  private var activeCompletions: [(BackgroundStepSyncResult) -> Void] = []
  private var trailingCompletions: [(BackgroundStepSyncResult) -> Void] = []

  init(
    stateStore: BackgroundStepSyncStateStoring,
    stepReader: StepReading,
    poster: StepPosting,
    now: @escaping () -> Date = Date.init,
    timeZoneIdentifier: @escaping () -> String = { TimeZone.current.identifier },
    appVersion: @escaping () -> String? = {
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    },
    newIdempotencyKey: @escaping () -> String = { UUID().uuidString.lowercased() },
    hasExecutionBudget: @escaping () -> Bool = { true }
  ) {
    self.stateStore = stateStore
    self.stepReader = stepReader
    self.poster = poster
    self.now = now
    self.timeZoneIdentifier = timeZoneIdentifier
    self.appVersion = appVersion
    self.newIdempotencyKey = newIdempotencyKey
    self.hasExecutionBudget = hasExecutionBudget
  }

  // Native uploads contain only closed clock-hour buckets. This avoids a
  // partial row blocking the finer foreground sample reconciler.
  static func hourlySamplesEnd(
    currentTime: Date,
    bucketMinutes: Int,
    calendar: Calendar = .current
  ) -> Date {
    _ = bucketMinutes // retained for source compatibility with existing callers
    return calendar.dateInterval(of: .hour, for: currentTime)?.start ?? currentTime
  }

  func performSync(completion: @escaping (BackgroundStepSyncResult) -> Void) {
    gate.async {
      if self.isRunning {
        self.trailingCompletions.append(completion)
        return
      }
      self.isRunning = true
      self.activeCompletions = [completion]
      self.runLogicalSync(wasRecovery: false) { result in
        self.finishRun(result)
      }
    }
  }

  private func finishRun(_ result: BackgroundStepSyncResult) {
    gate.async {
      let callbacks = self.activeCompletions
      self.activeCompletions = []
      callbacks.forEach { $0(result) }

      guard !self.trailingCompletions.isEmpty else {
        self.isRunning = false
        return
      }
      let trailing = self.trailingCompletions
      self.trailingCompletions = []
      self.activeCompletions = trailing
      guard self.hasExecutionBudget() else {
        self.finishRun(.noData)
        return
      }
      self.runLogicalSync(wasRecovery: false) { trailingResult in
        self.finishRun(trailingResult)
      }
    }
  }

  private func currentSession() -> BackgroundStepSyncSession? {
    guard
      stateStore.healthAuthorized,
      let token = stateStore.sessionToken, !token.isEmpty,
      let ownerID = stateStore.backendUserID, !ownerID.isEmpty,
      let baseURL = stateStore.backendBaseURL
    else { return nil }
    return BackgroundStepSyncSession(token: token, ownerID: ownerID, baseURL: baseURL)
  }

  private func sessionStillMatches(_ captured: BackgroundStepSyncSession) -> Bool {
    guard let current = currentSession() else { return false }
    return current.token == captured.token &&
      current.ownerID == captured.ownerID &&
      current.baseURL.absoluteString == captured.baseURL.absoluteString
  }

  private func runLogicalSync(
    wasRecovery: Bool,
    completion: @escaping (BackgroundStepSyncResult) -> Void
  ) {
    guard let session = currentSession() else {
      completion(.noData)
      return
    }

    if let rawLegacy = stateStore.pendingLegacyEnvelope {
      guard let envelope = decode(BackgroundStepSyncLegacyEnvelope.self, rawLegacy),
            Self.isValidLegacyEnvelope(envelope) else {
        guard sessionStillMatches(session) else { completion(.noData); return }
        if stateStore.pendingLegacyEnvelope == rawLegacy { stateStore.pendingLegacyEnvelope = nil }
        readFresh(session: session, forceLegacy: isNegativeCapabilityCurrent(session), completion: completion)
        return
      }
      guard matches(envelope.ownerID, envelope.backendBaseURL, session) else {
        clearOwnedLegacy(envelope)
        guard sessionStillMatches(session) else { completion(.noData); return }
        readFresh(session: session, forceLegacy: isNegativeCapabilityCurrent(session), completion: completion)
        return
      }
      sendLegacy(envelope, session: session) { result in
        guard result == .success, !wasRecovery else {
          completion(result)
          return
        }
        self.readFresh(session: session, forceLegacy: self.isNegativeCapabilityCurrent(session), completion: completion)
      }
      return
    }

    if let rawV2 = stateStore.pendingV2Envelope {
      guard let envelope = decode(BackgroundStepSyncV2Envelope.self, rawV2),
            Self.isValidV2Envelope(envelope) else {
        guard sessionStillMatches(session) else { completion(.noData); return }
        if stateStore.pendingV2Envelope == rawV2 { stateStore.pendingV2Envelope = nil }
        readFresh(session: session, forceLegacy: isNegativeCapabilityCurrent(session), completion: completion)
        return
      }
      guard matches(envelope.ownerID, envelope.backendBaseURL, session) else {
        clearOwnedV2(envelope)
        guard sessionStillMatches(session) else { completion(.noData); return }
        readFresh(session: session, forceLegacy: isNegativeCapabilityCurrent(session), completion: completion)
        return
      }
      sendV2(envelope, session: session, isRecovery: true, allowConflictRefresh: true, completion: completion)
      return
    }

    readFresh(session: session, forceLegacy: isNegativeCapabilityCurrent(session), completion: completion)
  }

  private func readFresh(
    session: BackgroundStepSyncSession,
    forceLegacy: Bool,
    completion: @escaping (BackgroundStepSyncResult) -> Void
  ) {
    let currentTime = now()
    let days = BackgroundStepSyncDateFormatter.localFallbackSyncDays(now: currentTime)
    stepReader.fetchStepCounts(for: days) { result in
      guard self.sessionStillMatches(session) else {
        completion(.noData)
        return
      }
      guard case .success(let dailySteps) = result,
            let daily = dailySteps.last else {
        completion(result.isFailure ? .failed : .noData)
        return
      }
      let start = Calendar.current.startOfDay(for: currentTime)
      let end = Self.hourlySamplesEnd(
        currentTime: currentTime,
        bucketMinutes: self.stateStore.stepSampleBucketMinutes
      )
      guard end > start else {
        self.createAndSend(daily: daily, samples: [], session: session, forceLegacy: forceLegacy, completion: completion)
        return
      }
      self.stepReader.fetchHourlyStepCounts(from: start, to: end) { hourlyResult in
        guard self.sessionStillMatches(session) else {
          completion(.noData)
          return
        }
        let samples: [[String: Any]]
        switch hourlyResult {
        case .success(let value): samples = value
        case .failure: samples = []
        }
        self.createAndSend(daily: daily, samples: samples, session: session, forceLegacy: forceLegacy, completion: completion)
      }
    }
  }

  private func createAndSend(
    daily: BackgroundDailyStep,
    samples: [[String: Any]],
    session: BackgroundStepSyncSession,
    forceLegacy: Bool,
    completion: @escaping (BackgroundStepSyncResult) -> Void
  ) {
    guard sessionStillMatches(session) else {
      completion(.noData)
      return
    }
    guard let body = try? JSONSerialization.data(
      withJSONObject: ["date": daily.date, "steps": daily.steps, "samples": samples],
      options: [.sortedKeys]
    ) else {
      completion(.failed)
      return
    }
    let timeZone = timeZoneIdentifier()
    if forceLegacy {
      guard let legacy = makeLegacyEnvelope(
        body: body, ownerID: session.ownerID,
        backendBaseURL: session.baseURL.absoluteString, timeZone: timeZone
      ) else {
        completion(.failed)
        return
      }
      guard sessionStillMatches(session) else { completion(.noData); return }
      stateStore.pendingLegacyEnvelope = encode(legacy)
      sendLegacy(legacy, session: session, completion: completion)
      return
    }
    let envelope = BackgroundStepSyncV2Envelope(
      ownerID: session.ownerID,
      backendBaseURL: session.baseURL.absoluteString,
      idempotencyKey: newIdempotencyKey(),
      timeZone: timeZone,
      body: body,
      createdAt: now()
    )
    guard sessionStillMatches(session) else { completion(.noData); return }
    stateStore.pendingV2Envelope = encode(envelope)
    sendV2(envelope, session: session, isRecovery: false, allowConflictRefresh: true, completion: completion)
  }

  private func sendV2(
    _ envelope: BackgroundStepSyncV2Envelope,
    session: BackgroundStepSyncSession,
    isRecovery: Bool,
    allowConflictRefresh: Bool,
    completion: @escaping (BackgroundStepSyncResult) -> Void
  ) {
    guard sessionStillMatches(session) else {
      clearOwnedV2(envelope)
      completion(.noData)
      return
    }
    guard hasExecutionBudget() else {
      completion(.noData)
      return
    }
    let request = BackgroundStepSyncV2Request(
      baseURL: session.baseURL, sessionToken: session.token,
      idempotencyKey: envelope.idempotencyKey, timeZone: envelope.timeZone,
      appVersion: appVersion(), body: envelope.body
    )
    postV2(request, envelope: envelope, session: session, attemptsRemaining: 2) { postResult in
      guard case .response(let response) = postResult else {
        completion(.noData)
        return
      }
      guard self.sessionStillMatches(session) else {
        self.clearOwnedV2(envelope)
        completion(.noData)
        return
      }
      guard let status = response.statusCode, response.error == nil else {
        completion(.failed) // immutable envelope remains for the next trigger
        return
      }
      if status == 202, Self.hasCapabilityMarker(response.body) {
        self.clearOwnedV2(envelope)
        self.clearNegativeCapabilityIfOwned(session)
        if isRecovery {
          guard self.sessionStillMatches(session) else { completion(.noData); return }
          self.readFresh(session: session, forceLegacy: false, completion: completion)
        } else {
          completion(.success)
        }
        return
      }
      if (200..<300).contains(status) {
        self.startLegacyFallback(envelope, session: session, completion: completion)
        return
      }
      if status == 404 || (status == 503 && Self.isAsyncDisabled(response.body)) {
        self.startLegacyFallback(envelope, session: session, completion: completion)
        return
      }
      if status == 409 {
        self.clearOwnedV2(envelope)
        guard allowConflictRefresh else { completion(.failed); return }
        guard self.sessionStillMatches(session) else { completion(.noData); return }
        self.readFreshAfterConflict(session: session, completion: completion)
        return
      }
      if [400, 401, 403, 413, 429].contains(status) {
        self.clearOwnedV2(envelope)
        completion([401, 403, 429].contains(status) ? .noData : .failed)
        return
      }
      completion(.failed) // retryable/unknown response retains the envelope
    }
  }

  private func readFreshAfterConflict(
    session: BackgroundStepSyncSession,
    completion: @escaping (BackgroundStepSyncResult) -> Void
  ) {
    // A fresh Health read produces a new immutable key/body. A second conflict
    // is terminal for this invocation and never selects legacy.
    let currentTime = now()
    stepReader.fetchStepCounts(for: BackgroundStepSyncDateFormatter.localFallbackSyncDays(now: currentTime)) { result in
      guard self.sessionStillMatches(session) else { completion(.noData); return }
      guard case .success(let values) = result, let daily = values.last else {
        completion(.failed)
        return
      }
      let start = Calendar.current.startOfDay(for: currentTime)
      let end = Self.hourlySamplesEnd(currentTime: currentTime, bucketMinutes: self.stateStore.stepSampleBucketMinutes)
      let finish: ([[String: Any]]) -> Void = { samples in
        guard self.sessionStillMatches(session) else { completion(.noData); return }
        guard let body = try? JSONSerialization.data(
          withJSONObject: ["date": daily.date, "steps": daily.steps, "samples": samples],
          options: [.sortedKeys]
        ) else { completion(.failed); return }
        let fresh = BackgroundStepSyncV2Envelope(
          ownerID: session.ownerID, backendBaseURL: session.baseURL.absoluteString,
          idempotencyKey: self.newIdempotencyKey(), timeZone: self.timeZoneIdentifier(),
          body: body, createdAt: self.now()
        )
        guard self.sessionStillMatches(session) else { completion(.noData); return }
        self.stateStore.pendingV2Envelope = self.encode(fresh)
        self.sendV2(fresh, session: session, isRecovery: false, allowConflictRefresh: false, completion: completion)
      }
      guard end > start else { finish([]); return }
      self.stepReader.fetchHourlyStepCounts(from: start, to: end) { hourly in
        if case .success(let samples) = hourly { finish(samples) } else { finish([]) }
      }
    }
  }

  private func postV2(
    _ request: BackgroundStepSyncV2Request,
    envelope: BackgroundStepSyncV2Envelope,
    session: BackgroundStepSyncSession,
    attemptsRemaining: Int,
    completion: @escaping (BackgroundStepPostResult) -> Void
  ) {
    guard sessionStillMatches(session) else {
      clearOwnedV2(envelope)
      completion(.sessionChanged)
      return
    }
    poster.postSyncV2(request) { response in
      guard self.sessionStillMatches(session) else {
        self.clearOwnedV2(envelope)
        completion(.sessionChanged)
        return
      }
      let retryable = response.error != nil || response.statusCode == nil ||
        ((500...599).contains(response.statusCode ?? 0) &&
          !(response.statusCode == 503 && Self.isAsyncDisabled(response.body)))
      guard retryable, attemptsRemaining > 1, self.hasExecutionBudget() else {
        completion(.response(response))
        return
      }
      guard self.sessionStillMatches(session) else {
        self.clearOwnedV2(envelope)
        completion(.sessionChanged)
        return
      }
      self.postV2(
        request, envelope: envelope, session: session,
        attemptsRemaining: attemptsRemaining - 1, completion: completion
      )
    }
  }

  private func startLegacyFallback(
    _ v2: BackgroundStepSyncV2Envelope,
    session: BackgroundStepSyncSession,
    completion: @escaping (BackgroundStepSyncResult) -> Void
  ) {
    guard sessionStillMatches(session) else {
      clearOwnedV2(v2)
      completion(.noData)
      return
    }
    guard let legacy = makeLegacyEnvelope(
      body: v2.body, ownerID: v2.ownerID,
      backendBaseURL: v2.backendBaseURL, timeZone: v2.timeZone
    ) else { completion(.failed); return }
    guard sessionStillMatches(session) else {
      clearOwnedV2(v2)
      completion(.noData)
      return
    }
    // Persist the staged pair before releasing the v2 envelope so a crash
    // cannot lose the logical upload between protocols.
    stateStore.pendingLegacyEnvelope = encode(legacy)
    guard sessionStillMatches(session) else {
      clearOwnedV2(v2)
      clearOwnedLegacy(legacy)
      completion(.noData)
      return
    }
    cacheNegativeCapability(session)
    clearOwnedV2(v2)
    sendLegacy(legacy, session: session, completion: completion)
  }

  private func sendLegacy(
    _ initial: BackgroundStepSyncLegacyEnvelope,
    session: BackgroundStepSyncSession,
    completion: @escaping (BackgroundStepSyncResult) -> Void
  ) {
    guard sessionStillMatches(session) else {
      clearOwnedLegacy(initial)
      completion(.noData)
      return
    }
    guard hasExecutionBudget() else {
      completion(.noData)
      return
    }
    var envelope = initial
    func persist(replacing previous: BackgroundStepSyncLegacyEnvelope) -> Bool {
      guard self.sessionStillMatches(session), self.legacyEnvelopeStillMatches(previous) else {
        self.clearOwnedLegacy(previous)
        return false
      }
      self.stateStore.pendingLegacyEnvelope = self.encode(envelope)
      return true
    }
    func sendSamples() {
      guard self.sessionStillMatches(session) else {
        self.clearOwnedLegacy(envelope)
        completion(.noData)
        return
      }
      guard !envelope.samplesComplete else {
        self.clearOwnedLegacy(envelope)
        completion(.success)
        return
      }
      guard self.hasExecutionBudget() else {
        completion(.noData)
        return
      }
      let request = BackgroundStepLegacyRequest(
        baseURL: session.baseURL, path: "/steps/samples", sessionToken: session.token,
        timeZone: envelope.timeZone, body: envelope.samplesBody
      )
      self.poster.postLegacy(request) { response in
        guard self.sessionStillMatches(session) else {
          self.clearOwnedLegacy(envelope)
          completion(.noData)
          return
        }
        guard let status = response.statusCode, response.error == nil else {
          completion(.failed); return
        }
        if (200..<300).contains(status) {
          let previous = envelope
          envelope.samplesComplete = true
          guard persist(replacing: previous) else { completion(.noData); return }
          self.clearOwnedLegacy(envelope)
          completion(.success)
        } else if [400, 401, 403, 413, 429].contains(status) {
          self.clearOwnedLegacy(envelope)
          completion([401, 403, 429].contains(status) ? .noData : .failed)
        } else {
          completion(.failed)
        }
      }
    }
    guard !envelope.dailyComplete else { sendSamples(); return }
    let request = BackgroundStepLegacyRequest(
      baseURL: session.baseURL, path: "/steps", sessionToken: session.token,
      timeZone: envelope.timeZone, body: envelope.dailyBody
    )
    guard sessionStillMatches(session) else {
      clearOwnedLegacy(envelope)
      completion(.noData)
      return
    }
    poster.postLegacy(request) { response in
      guard self.sessionStillMatches(session) else {
        self.clearOwnedLegacy(envelope)
        completion(.noData)
        return
      }
      guard let status = response.statusCode, response.error == nil else {
        completion(.failed); return
      }
      if (200..<300).contains(status) {
        let previous = envelope
        envelope.dailyComplete = true
        guard persist(replacing: previous) else { completion(.noData); return }
        sendSamples()
      } else if [400, 401, 403, 413, 429].contains(status) {
        self.clearOwnedLegacy(envelope)
        completion([401, 403, 429].contains(status) ? .noData : .failed)
      } else {
        completion(.failed)
      }
    }
  }

  private func makeLegacyEnvelope(
    body: Data, ownerID: String, backendBaseURL: String, timeZone: String
  ) -> BackgroundStepSyncLegacyEnvelope? {
    guard let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          let date = payload["date"] as? String,
          let steps = payload["steps"] as? Int,
          let samples = payload["samples"] as? [[String: Any]],
          let daily = try? JSONSerialization.data(
            withJSONObject: ["date": date, "steps": steps, "skipRaceResolution": true],
            options: [.sortedKeys]
          ),
          let sampleBody = try? JSONSerialization.data(
            withJSONObject: ["samples": samples], options: [.sortedKeys]
          ) else { return nil }
    return BackgroundStepSyncLegacyEnvelope(
      ownerID: ownerID, backendBaseURL: backendBaseURL, timeZone: timeZone,
      dailyBody: daily, samplesBody: sampleBody,
      dailyComplete: false, samplesComplete: samples.isEmpty
    )
  }

  private func matches(_ ownerID: String, _ backendURL: String, _ session: BackgroundStepSyncSession) -> Bool {
    ownerID == session.ownerID && backendURL == session.baseURL.absoluteString
  }

  private func sameV2(_ lhs: BackgroundStepSyncV2Envelope, _ rhs: BackgroundStepSyncV2Envelope) -> Bool {
    lhs.ownerID == rhs.ownerID && lhs.backendBaseURL == rhs.backendBaseURL &&
      lhs.idempotencyKey == rhs.idempotencyKey && lhs.timeZone == rhs.timeZone &&
      lhs.body == rhs.body && lhs.createdAt == rhs.createdAt
  }

  private func sameLegacy(
    _ lhs: BackgroundStepSyncLegacyEnvelope,
    _ rhs: BackgroundStepSyncLegacyEnvelope
  ) -> Bool {
    lhs.ownerID == rhs.ownerID && lhs.backendBaseURL == rhs.backendBaseURL &&
      lhs.timeZone == rhs.timeZone && lhs.dailyBody == rhs.dailyBody &&
      lhs.samplesBody == rhs.samplesBody && lhs.dailyComplete == rhs.dailyComplete &&
      lhs.samplesComplete == rhs.samplesComplete
  }

  private func clearOwnedV2(_ expected: BackgroundStepSyncV2Envelope) {
    guard let raw = stateStore.pendingV2Envelope,
          let current = decode(BackgroundStepSyncV2Envelope.self, raw),
          sameV2(current, expected) else { return }
    stateStore.pendingV2Envelope = nil
  }

  private func legacyEnvelopeStillMatches(_ expected: BackgroundStepSyncLegacyEnvelope) -> Bool {
    guard let raw = stateStore.pendingLegacyEnvelope,
          let current = decode(BackgroundStepSyncLegacyEnvelope.self, raw) else { return false }
    return sameLegacy(current, expected)
  }

  private func clearOwnedLegacy(_ expected: BackgroundStepSyncLegacyEnvelope) {
    guard legacyEnvelopeStillMatches(expected) else { return }
    stateStore.pendingLegacyEnvelope = nil
  }

  private func isNegativeCapabilityCurrent(_ session: BackgroundStepSyncSession) -> Bool {
    guard sessionStillMatches(session) else { return false }
    guard let raw = stateStore.negativeCapability else { return false }
    guard let value = decode(BackgroundStepSyncNegativeCapability.self, raw) else {
      if sessionStillMatches(session), stateStore.negativeCapability == raw {
        stateStore.negativeCapability = nil
      }
      return false
    }
    guard matches(value.ownerID, value.backendBaseURL, session), value.unsupportedUntil > now() else {
      if sessionStillMatches(session), stateStore.negativeCapability == raw {
        stateStore.negativeCapability = nil
      }
      return false
    }
    return true
  }

  private func cacheNegativeCapability(_ session: BackgroundStepSyncSession) {
    guard sessionStillMatches(session) else { return }
    let value = BackgroundStepSyncNegativeCapability(
      ownerID: session.ownerID, backendBaseURL: session.baseURL.absoluteString,
      unsupportedUntil: now().addingTimeInterval(24 * 60 * 60)
    )
    stateStore.negativeCapability = encode(value)
  }

  private func clearNegativeCapabilityIfOwned(_ session: BackgroundStepSyncSession) {
    guard sessionStillMatches(session), let raw = stateStore.negativeCapability else { return }
    guard let value = decode(BackgroundStepSyncNegativeCapability.self, raw) else {
      if stateStore.negativeCapability == raw { stateStore.negativeCapability = nil }
      return
    }
    guard matches(value.ownerID, value.backendBaseURL, session),
          stateStore.negativeCapability == raw else { return }
    stateStore.negativeCapability = nil
  }

  private func encode<T: Encodable>(_ value: T) -> String? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private func decode<T: Decodable>(_ type: T.Type, _ raw: String) -> T? {
    guard let data = raw.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  private static func hasCapabilityMarker(_ body: Data?) -> Bool {
    guard let body,
          let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return false }
    return json["stepIntakeSemantics"] as? String == "CANONICAL_SOURCE_QUEUE_V1"
  }

  private static func isAsyncDisabled(_ body: Data?) -> Bool {
    guard let body,
          let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return false }
    return json["code"] as? String == "ASYNC_DISABLED"
  }

  private static func isValidV2Envelope(_ envelope: BackgroundStepSyncV2Envelope) -> Bool {
    guard !envelope.ownerID.isEmpty, URL(string: envelope.backendBaseURL) != nil,
          UUID(uuidString: envelope.idempotencyKey) != nil, !envelope.timeZone.isEmpty,
          let payload = try? JSONSerialization.jsonObject(with: envelope.body) as? [String: Any],
          payload["date"] is String, payload["steps"] is Int,
          payload["samples"] is [[String: Any]] else { return false }
    return true
  }

  private static func isValidLegacyEnvelope(_ envelope: BackgroundStepSyncLegacyEnvelope) -> Bool {
    guard !envelope.ownerID.isEmpty, URL(string: envelope.backendBaseURL) != nil,
          !envelope.timeZone.isEmpty,
          let daily = try? JSONSerialization.jsonObject(with: envelope.dailyBody) as? [String: Any],
          daily["date"] is String, daily["steps"] is Int,
          let samples = try? JSONSerialization.jsonObject(with: envelope.samplesBody) as? [String: Any],
          samples["samples"] is [[String: Any]] else { return false }
    return true
  }
}

private extension Result {
  var isFailure: Bool {
    if case .failure = self { return true }
    return false
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

  // Fix C1: Dart persists these via the legacy shared_preferences plugin, which
  // prepends "flutter." to every key in the standard NSUserDefaults suite. Native
  // MUST read the prefixed keys, or every read is nil/false and the background-sync
  // guard exits .noData — the bug that made iOS background sync dead in every
  // shipped binary. Cheap-token: standard suite, same process, no Keychain.
  var sessionToken: String? {
    userDefaults.string(forKey: "flutter.auth_session_token")
  }

  var backendUserID: String? {
    userDefaults.string(forKey: "flutter.auth_backend_user_id")
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
    userDefaults.bool(forKey: "flutter.health_authorized")
  }

  // Mirrors AuthService._keyStepSampleBucketMinutes (auth_service.dart) — the
  // last backend-accepted featureFlags.stepSampleBucketMinutes value. Absent
  // (0) or out-of-set values resolve to 60 (hourly), matching the Dart
  // resolver, so a missing/renamed pref can only ever restore legacy behavior.
  var stepSampleBucketMinutes: Int {
    let raw = userDefaults.integer(forKey: "flutter.auth_step_sample_bucket_minutes")
    return [5, 10, 15, 30, 60].contains(raw) ? raw : 60
  }

  var pendingV2Envelope: String? {
    get { userDefaults.string(forKey: BackgroundSyncBootstrapKeys.iosPendingV2) }
    set { setString(newValue, forKey: BackgroundSyncBootstrapKeys.iosPendingV2) }
  }

  var pendingLegacyEnvelope: String? {
    get { userDefaults.string(forKey: BackgroundSyncBootstrapKeys.iosPendingLegacy) }
    set { setString(newValue, forKey: BackgroundSyncBootstrapKeys.iosPendingLegacy) }
  }

  var negativeCapability: String? {
    get { userDefaults.string(forKey: BackgroundSyncBootstrapKeys.iosNegativeCapability) }
    set { setString(newValue, forKey: BackgroundSyncBootstrapKeys.iosNegativeCapability) }
  }

  private func setString(_ value: String?, forKey key: String) {
    if let value { userDefaults.set(value, forKey: key) }
    else { userDefaults.removeObject(forKey: key) }
  }
}

struct BackgroundSyncBootstrapKeys {
  // Fix C1: "flutter." prefix to match what Dart's legacy shared_preferences writes.
  static let backendBaseURL = "flutter.background_sync_backend_base_url"
  static let iosPendingV2 = "flutter.ios_background_sync_v2_pending"
  static let iosPendingLegacy = "flutter.ios_background_sync_legacy_pending"
  static let iosNegativeCapability = "flutter.ios_background_sync_negative_capability"
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
      let timePredicate = HKQuery.predicateForSamples(
        withStart: syncDay.startsAt,
        end: syncDay.endsAt,
        options: .strictStartDate
      )
      // Exclude manually entered steps so the native path matches Dart's
      // getTotalStepsInInterval(includeManualEntry: false).
      let manualPredicate = HKQuery.predicateForObjects(
        withMetadataKey: HKMetadataKeyWasUserEntered,
        operatorType: .notEqualTo,
        value: true
      )
      let predicate = NSCompoundPredicate(
        andPredicateWithSubpredicates: [timePredicate, manualPredicate]
      )

      // cumulativeSum is Apple's own cross-source merge (the value the Health
      // app shows), not a naive sum of every source — HealthKit reconciles
      // iPhone + Watch + other wearables via source priority for us.
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

    let timePredicate = HKQuery.predicateForSamples(
      withStart: startDate,
      end: endDate,
      options: .strictStartDate
    )
    // Exclude manually entered steps so the native path matches Dart's
    // getTotalStepsInInterval(includeManualEntry: false).
    let manualPredicate = HKQuery.predicateForObjects(
      withMetadataKey: HKMetadataKeyWasUserEntered,
      operatorType: .notEqualTo,
      value: true
    )
    let predicate = NSCompoundPredicate(
      andPredicateWithSubpredicates: [timePredicate, manualPredicate]
    )

    // cumulativeSum is Apple's own cross-source merge (the value the Health
    // app shows), not a naive sum of every source — HealthKit reconciles
    // iPhone + Watch + other wearables via source priority for us.
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
        // Never emit a bucket that runs past `endDate`. `statistics.startDate` /
        // `endDate` are the ANCHORED full clock hour, not the clamped query
        // range, so the bucket at the cutoff still reports 14:00→15:00 even when
        // `hourlySamplesEnd` floored the query to 14:00 — and `.cumulativeSum`
        // makes it non-zero whenever a recording chunk straddles the boundary
        // (the same straddle documented in health_service.dart). A row whose
        // period_end is in the future is scored as an open bucket (no powerup
        // credit) AND permanently blocks the Dart 5-min sync for that hour: the
        // backend reconcile span guard (stepSample.js rule 2) rejects every
        // finer sample overlapping a stored row the batch doesn't fully span.
        // 2026-07-26: wedged a live 3x Ghost Pepper / Runner's High hour at 7 steps.
        guard statistics.endDate <= endDate else { return }
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

  func postSyncV2(
    _ value: BackgroundStepSyncV2Request,
    completion: @escaping (BackgroundStepHTTPResponse) -> Void
  ) {
    guard let url = URL(string: "/steps/sync-v2", relativeTo: value.baseURL)?.absoluteURL else {
      completion(BackgroundStepHTTPResponse(statusCode: nil, body: nil, error: URLError(.badURL)))
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = value.body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(value.sessionToken)", forHTTPHeaderField: "Authorization")
    request.setValue(value.idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
    request.setValue(value.timeZone, forHTTPHeaderField: "X-Timezone")
    if let appVersion = value.appVersion, !appVersion.isEmpty {
      request.setValue(appVersion, forHTTPHeaderField: "X-App-Version")
    }
    session.dataTask(with: request) { data, response, error in
      completion(BackgroundStepHTTPResponse(
        statusCode: (response as? HTTPURLResponse)?.statusCode,
        body: data,
        error: error
      ))
    }.resume()
  }

  func postLegacy(
    _ value: BackgroundStepLegacyRequest,
    completion: @escaping (BackgroundStepHTTPResponse) -> Void
  ) {
    guard let url = URL(string: value.path, relativeTo: value.baseURL)?.absoluteURL else {
      completion(BackgroundStepHTTPResponse(statusCode: nil, body: nil, error: URLError(.badURL)))
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = value.body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(value.sessionToken)", forHTTPHeaderField: "Authorization")
    request.setValue(value.timeZone, forHTTPHeaderField: "X-Timezone")
    session.dataTask(with: request) { data, response, error in
      completion(BackgroundStepHTTPResponse(
        statusCode: (response as? HTTPURLResponse)?.statusCode,
        body: data,
        error: error
      ))
    }.resume()
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
    // Fix C2: parity with the Dart foreground path — without X-Timezone the backend
    // defaults to America/New_York, double-counting steps across the day boundary for
    // non-ET users (which can falsely "finish" a race).
    request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "X-Timezone")

    do {
      // Fix C3: skipRaceResolution parity. The background coordinator always posts
      // today's hourly samples right after this daily post; deferring race
      // resolution to the (more precise) samples post — and to the Phase 0 cron —
      // matches Dart and avoids resolving on partial daily data.
      request.httpBody = try JSONSerialization.data(withJSONObject: [
        "steps": steps,
        "date": date,
        "skipRaceResolution": true,
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
    // Fix C2: same X-Timezone parity as the daily post above.
    request.setValue(TimeZone.current.identifier, forHTTPHeaderField: "X-Timezone")

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
