import Flutter
import UIKit
import UserNotifications
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var notificationChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    if let bundleIdentifier = Bundle.main.bundleIdentifier {
      WorkmanagerPlugin.registerTask(
        withIdentifier: "\(bundleIdentifier).periodicStepSync"
      )
    }

    // Set up notification method channel
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

    UNUserNotificationCenter.current().delegate = self

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func requestNotificationPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(
      options: [.alert, .badge, .sound]
    ) { granted, error in
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

  // Show notification banner when app is in foreground
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  // Handle notification tap
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
}
