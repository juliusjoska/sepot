import CallKit
import Flutter
import PushKit
import UIKit
import WebRTC
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate, CallkitIncomingAppDelegate {
  // PushKit registry musí žít po celou dobu běhu appky, jinak VoIP pushe nechodí.
  private var voipRegistry: PKPushRegistry?
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

    // Hovory: VoIP push z relaye → CallKit.
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry

    // Zvukovou relaci u hovoru řídí CallKit; WebRTC ji smí zapnout až po
    // jeho aktivaci (didActivateAudioSession), jinak hovor z uzamčené
    // obrazovky nemá zvuk.
    RTCAudioSession.sharedInstance().useManualAudio = true
    RTCAudioSession.sharedInstance().isAudioEnabled = false

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - PushKit (VoIP)

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  // iOS vyžaduje, aby každý VoIP push HNED skončil hovorem v CallKitu — jinak
  // appku ukončí a po opakování VoIP pushe přestane doručovat. Relay neví,
  // kdo volá (sealed sender), proto zvoní „Šepot“; Dart zvonění spáruje
  // s nabídkou podle `extra.push`, až ji po připojení dešifruje.
  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    let data = flutter_callkit_incoming.Data(
      id: UUID().uuidString, nameCaller: "Šepot", handle: "Šepot", type: 0)
    data.appName = "Šepot"
    data.duration = 45000
    data.extra = ["push": true]
    data.handleType = "generic"
    data.supportsVideo = true
    data.maximumCallGroups = 1
    data.maximumCallsPerCallGroup = 1
    data.supportsHolding = false
    data.supportsDTMF = false
    data.includesCallsInRecents = false
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true) {
      completion()
    }
    // Běží-li Dart, ať se hned připojí a vyzvedne nabídku z fronty.
    apnsChannel?.invokeMethod("onWake", arguments: nil)
  }

  // MARK: - CallKit
  // Rozhodnutí (přijmout/odmítnout) řeší Dart přes události pluginu;
  // tady jen potvrdit akci CallKitu, jinak by ji systém po čase zrušil.

  func onAccept(_ call: Call, _ action: CXAnswerCallAction) {
    action.fulfill()
  }

  func onDecline(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onEnd(_ call: Call, _ action: CXEndCallAction) {
    action.fulfill()
  }

  func onTimeOut(_ call: Call) {}

  func didActivateAudioSession(_ audioSession: AVAudioSession) {
    RTCAudioSession.sharedInstance().audioSessionDidActivate(audioSession)
    RTCAudioSession.sharedInstance().isAudioEnabled = true
  }

  func didDeactivateAudioSession(_ audioSession: AVAudioSession) {
    RTCAudioSession.sharedInstance().audioSessionDidDeactivate(audioSession)
    RTCAudioSession.sharedInstance().isAudioEnabled = false
  }

  func providerDidReset() {}

  // APNs vydal device token → předáme Dartu (ten ho pošle relayi).
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Foundation.Data
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
