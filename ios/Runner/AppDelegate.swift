import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Rain notifications: register the BGTaskScheduler identifier declared in
    // Info.plist so iOS can hand this app periodic background execution to run
    // the rain check. The identifier MUST match the one used on the Dart side
    // in rain_notification_service_io.dart and in Info.plist.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.example.flutter_weather.rainCheck",
      frequency: NSNumber(value: 15 * 60)
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
