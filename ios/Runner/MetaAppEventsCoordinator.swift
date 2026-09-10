import AppTrackingTransparency
import Flutter
import UIKit
import UserMessagingPlatform

/// Owns the process-lifetime native boundary. Creating this object registers
/// lifecycle observers but does not initialize or touch Meta's singleton SDKs.
final class MetaAppEventsCoordinator {
  private var channel: FlutterMethodChannel?
  private var observers: [NSObjectProtocol] = []
  private let lifecycle: MetaAppEventsLifecycle

  init(application: UIApplication, launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
    let sdk = MetaCoreKitAdapter(application: application, launchOptions: launchOptions)
    lifecycle = MetaAppEventsLifecycle(sdk: sdk, permission: { resolved in
      // Debug's native include is optional: missing/unresolved settings must
      // disable measurement rather than reaching a CoreKit configuration error.
      guard MetaAppEventsPolicy.hasConfiguration(Bundle.main.infoDictionary ?? [:]) else { return .denied }
      var values: [String: Any] = [:]
      for key in MetaAppEventsPolicy.signalKeys {
        values[key] = UserDefaults.standard.object(forKey: key)
      }
      let status: MetaCMPStatus
      switch ConsentInformation.shared.consentStatus {
      case .obtained: status = .obtained
      case .notRequired: status = .notRequired
      case .required: status = .required
      default: status = .unknown
      }
      let attAuthorized: Bool
      if #available(iOS 14, *) {
        attAuthorized = ATTrackingManager.trackingAuthorizationStatus == .authorized
      } else {
        attAuthorized = false
      }
      return MetaAppEventsPolicy.evaluate(resolved: resolved, status: status,
                                          values: values, attAuthorized: attAuthorized)
    }, isForeground: { application.applicationState == .active })

    // Register before delayed SDK initialization. NotificationCenter does not
    // promise observer priority; the real SDK resume fixture verifies ordering.
    observers.append(NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.lifecycle.becameActive() })
    observers.append(NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.lifecycle.enteredBackground() })
  }

  func attach(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.steptracker/meta_app_events", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, Thread.isMainThread else { result(false); return }
      guard let arguments = call.arguments as? [String: Any], arguments.count == 1 else {
        result(false); return
      }
      switch call.method {
      case "updateConsent":
        guard let resolved = arguments["resolved"] as? Bool else { result(false); return }
        self.lifecycle.updateConsent(resolved: resolved)
        result(true)
      case "logEvent":
        guard let event = arguments["event"] as? String else { result(false); return }
        result(self.lifecycle.log(event: event))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    observers.forEach(NotificationCenter.default.removeObserver)
    channel?.setMethodCallHandler(nil)
  }
}
