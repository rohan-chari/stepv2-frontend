// Isolated simulator fixture. All HTTP(S) is intercepted, with fixture Meta
// credentials supplied by run_meta_sdk_smoke.py. Never part of the shipped app.
import FBSDKCoreKit
import Foundation
import UIKit
import zlib
import ObjectiveC

private extension URLSessionConfiguration {
  @objc class func metaFixtureDefault() -> URLSessionConfiguration {
    let configuration = metaFixtureDefault() // Original getter after exchange.
    configuration.protocolClasses = [FixtureProtocol.self]
    return configuration
  }
  static func installFixtureProtocol() {
    let original = class_getClassMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.default))!
    let replacement = class_getClassMethod(URLSessionConfiguration.self, #selector(metaFixtureDefault))!
    method_exchangeImplementations(original, replacement)
    precondition(URLSessionConfiguration.default.protocolClasses?.first == FixtureProtocol.self)
  }
}

private final class FixtureProtocol: URLProtocol {
  static var bodies: [String] = []
  static let lock = NSLock()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    var body = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var bytes = [UInt8](repeating: 0, count: 8192)
      while true {
        let count = stream.read(&bytes, maxLength: bytes.count)
        if count <= 0 { break }
        body.append(contentsOf: bytes.prefix(count))
      }
    }
    if body.starts(with: [0x1f, 0x8b]) { body = Self.inflate(body) }
    let text = String(data: body, encoding: .utf8) ?? ""
    Self.lock.lock(); Self.bodies.append(text); Self.lock.unlock()
    let configuration: [String: Any] = ["success": true, "data": [], "app_events_session_timeout": 1,
      "app_events_config": ["event_collection_enabled": true, "advertiser_id_collection_enabled": false,
                            "default_ate_status": false], "supports_implicit_sdk_logging": false]
    var response: Any = configuration
    if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
       let batch = json["batch"] as? String,
       let batchData = batch.data(using: .utf8),
       let requests = try? JSONSerialization.jsonObject(with: batchData) as? [Any] {
      let bodyString = String(data: try! JSONSerialization.data(withJSONObject: configuration), encoding: .utf8)!
      response = requests.map { _ in ["code": 200, "body": bodyString] as [String: Any] }
    }
    let data = try! JSONSerialization.data(withJSONObject: response)
    let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                               headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
  static func snapshot() -> [String] {
    lock.lock(); defer { lock.unlock() }; return bodies
  }
  static func inflate(_ data: Data) -> Data {
    var stream = z_stream()
    guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return Data() }
    defer { inflateEnd(&stream) }
    return data.withUnsafeBytes { buffer in
      stream.next_in = UnsafeMutablePointer(mutating: buffer.bindMemory(to: Bytef.self).baseAddress)
      stream.avail_in = uInt(data.count)
      var output = Data()
      var status: Int32 = Z_OK
      repeat {
        var bytes = [UInt8](repeating: 0, count: 16384)
        status = bytes.withUnsafeMutableBytes { buffer in
          stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
          stream.avail_out = uInt(buffer.count)
          return zlib.inflate(&stream, Z_NO_FLUSH)
        }
        output.append(contentsOf: bytes.prefix(16384 - Int(stream.avail_out)))
      } while status == Z_OK
      return status == Z_STREAM_END ? output : Data()
    }
  }
}

@main
final class SmokeDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?
  private var lifecycle: MetaAppEventsLifecycle!
  private var observers: [NSObjectProtocol] = []
  private var checks: [String: Bool] = [:]
  private var started = false
  private var awaitingLongResume = false
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    URLProtocol.registerClass(FixtureProtocol.self)
    URLSessionConfiguration.installFixtureProtocol()
    lifecycle = MetaAppEventsLifecycle(sdk: MetaCoreKitAdapter(application: application, launchOptions: options),
      permission: { resolved in resolved ? MetaPermission(collection: true, advertiserID: false) : .denied },
      isForeground: { application.applicationState == .active })
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
      object: nil, queue: .main) { [weak self] _ in
        guard let self else { return }
        self.lifecycle.becameActive()
        if self.awaitingLongResume {
          self.awaitingLongResume = false
          DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.finishAfterLongResume() }
        }
      })
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
      object: nil, queue: .main) { [weak self] _ in self?.lifecycle.enteredBackground() })
    return true
  }
  func startTest() {
    guard !started else { return }
    started = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
      self.checks["host_foreground"] = UIApplication.shared.applicationState == .active
      self.checks["no_sdk_requests_before_consent"] = FixtureProtocol.snapshot().isEmpty
      self.lifecycle.updateConsent(resolved: true)
      self.checks["autolog_disabled"] = !Settings.shared.isAutoLogAppEventsEnabled
      self.checks["advertiser_id_disabled"] = !Settings.shared.isAdvertiserIDCollectionEnabled
      self.checks["allowlisted_event_accepted"] = self.lifecycle.log(event: "shopViewed")
      self.checks["signup_rejected"] = !self.lifecycle.log(event: "registrationCompleted")
      AppEvents.shared.flush()
      DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.resumeAndWithdraw() }
    }
  }
  private func resumeAndWithdraw() {
    let before = FixtureProtocol.snapshot()
    checks["actual_sdk_activation_serialized"] = before.contains { $0.contains("fb_mobile_activate_app") }
    checks["actual_sdk_install_serialized"] = before.contains { $0.contains("MOBILE_APP_INSTALL") }
    checks["actual_sdk_shop_event_serialized"] = before.contains { $0.contains("bara_shop_viewed") }
    lifecycle.becameActive()
    NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: UIApplication.shared)
    NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: UIApplication.shared)
    lifecycle.updateConsent(resolved: false)
    checks["withdrawal_blocks_new_event"] = !lifecycle.log(event: "raceJoined")
    checks["withdrawal_explicit_flush_only"] = AppEvents.shared.flushBehavior == .explicitOnly
    checks["withdrawal_disables_id"] = !Settings.shared.isAdvertiserIDCollectionEnabled
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      let bodies = FixtureProtocol.snapshot()
      self.checks["withdrawn_event_never_serialized"] = !bodies.contains { $0.contains("bara_race_joined") }
      // SDK sessions coalesce quick background/resume; measure serialized
      // events separately from the lifecycle unit harness invocation count.
      let activationRequests = bodies.filter { $0.contains("fb_mobile_activate_app") }.count
      self.checks["quick_resume_coalesces_activation"] = activationRequests == 1
      self.lifecycle.updateConsent(resolved: true)
      self.awaitingLongResume = true
      let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      try! Data().write(to: directory.appendingPathComponent("ready-for-background"))
    }
  }
  private func finishAfterLongResume() {
    let bodies = FixtureProtocol.snapshot()
    let activationRequests = bodies.filter { $0.contains("fb_mobile_activate_app") }.count
    checks["expired_session_resume_serializes_second_activation"] = activationRequests == 2
    checks["expired_session_serializes_deactivation"] = bodies.contains { $0.contains("fb_mobile_deactivate_app") }
    let result: [String: Any] = ["checks": checks,
      "passed": checks.values.allSatisfy { $0 }, "intercepted_request_count": bodies.count,
      "activation_request_count": activationRequests, "sdk_version": Settings.shared.sdkVersion,
      "fixture_server_session_timeout_seconds": 1]
    let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("meta-sdk-smoke.json")
    try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
  }
}

@objc(SmokeSceneDelegate)
final class SmokeSceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
             options connectionOptions: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: scene)
    window.rootViewController = UIViewController()
    window.makeKeyAndVisible()
    self.window = window
  }
  func sceneDidBecomeActive(_ scene: UIScene) {
    (UIApplication.shared.delegate as? SmokeDelegate)?.startTest()
  }
}
