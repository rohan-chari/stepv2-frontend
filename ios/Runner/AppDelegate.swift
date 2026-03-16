import Flutter
import UIKit
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate {
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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
