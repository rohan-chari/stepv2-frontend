import FBSDKCoreKit
import UIKit

/// Public APIs of the pinned CoreKit only. Withdrawal stops Bara events and
/// ordinary auto-flush, not in-flight requests or all internal SDK persistence.
final class MetaCoreKitAdapter: MetaAppEventsSDK {
  private let application: UIApplication
  private let launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  init(application: UIApplication, launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
    self.application = application
    self.launchOptions = launchOptions
  }
  func initialize(advertiserID: Bool) {
    // Info.plist supplies safe pre-init defaults. CoreKit configures its
    // dependencies synchronously here; do not call AppEvents setters earlier.
    ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
    AppEvents.shared.flushBehavior = .explicitOnly
    setTrackingPermission(advertiserID)
    Settings.shared.isAutoLogAppEventsEnabled = false
  }
  func resume(advertiserID: Bool) {
    setTrackingPermission(advertiserID)
    AppEvents.shared.flushBehavior = .auto
  }
  func suspend() {
    AppEvents.shared.flushBehavior = .explicitOnly
    setTrackingPermission(false)
  }
  private func setTrackingPermission(_ enabled: Bool) {
    Settings.shared.isAdvertiserIDCollectionEnabled = enabled
    // CoreKit 18 reads ATT directly on iOS17+, while iOS14-16 still use
    // the public advertiser-tracking setter. Both use the same Meta+ATT gate.
    if #unavailable(iOS 17) {
      Settings.shared.isAdvertiserTrackingEnabled = enabled
    }
  }
  func activate() { AppEvents.shared.activateApp() }
  func log(name: String) { AppEvents.shared.logEvent(AppEvents.Name(rawValue: name)) }
}
