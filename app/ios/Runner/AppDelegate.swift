import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var apnsChannel: FlutterMethodChannel?
  // Token dorazí asynchronně z APNs; když si o něj Dart řekne dřív, podržíme ho.
  private var pendingToken: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "cz.sepot.sepot/apns", binaryMessenger: controller.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "register":
        // Nativní APNs registrace (bez Firebase) — token přijde v callbacku
        application.registerForRemoteNotifications()
        result(nil)
      case "getToken":
        result(self?.pendingToken)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    apnsChannel = channel

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // APNs vydal device token → předáme Dartu (ten ho pošle relayi).
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    pendingToken = token
    apnsChannel?.invokeMethod("onToken", arguments: token)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("APNs registrace selhala: \(error.localizedDescription)")
  }

  // Tichý „background" budíček z relaye (content-available:1). Probudí Dart,
  // ať se připojí na WS a vyleje frontu. Obsah nikdy neneseme.
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    apnsChannel?.invokeMethod("onWake", arguments: nil)
    // Dej WS chvíli na doručení; iOS background okno je krátké.
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
      completionHandler(.newData)
    }
  }
}
