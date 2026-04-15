import AVFoundation
import Flutter
import PushKit
import UIKit
import UserNotifications
import flutter_callkit_incoming

/// UserDefaults key used by `flutter_callkit_incoming` for the VoIP token (`DevicePushTokenVoIP`).
private let kFlutterCallKitVoipTokenDefaultsKey = "DevicePushTokenVoIP"

/// Raw PushKit token as base64 (Sygnal / Matrix HTTP pusher `pushkey` default format).
private let kMatrixSygnalVoipPushKeyDefaultsKey = "MatrixSygnalVoipPushKeyB64"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  private static let microphoneChannelName = "dev.inve.matrixchat/microphone"
  private static let voipMatrixPusherChannelName = "dev.inve.matrixchat/voip_matrix_pusher"

  private var voipRegistry: PKPushRegistry?
  private var voipMatrixPusherChannel: FlutterMethodChannel?
  /// Latest VoIP token for Sygnal (base64); mirrors UserDefaults while process is alive.
  private var lastVoipTokenSygnalB64: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // FCM on iOS needs an APNs device token. Register early so the token exists before Dart
    // calls [FirebaseMessaging.getAPNSToken] / [getToken] (see matrix_notifications_coordinator).
    UNUserNotificationCenter.current().delegate = self

    // VoIP push for CallKit when the app is suspended or not running (see PUSHKIT.md in
    // flutter_callkit_incoming). Server must use apns-push-type: voip and topic <bundle-id>.voip.
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [PKPushType.voIP]
    voipRegistry = registry

    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(
      name: AppDelegate.microphoneChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestAccess":
        // Recording apps should use AVAudioSession; this registers mic with the system and
        // shows NSMicrophoneUsageDescription. permission_handler uses AVCaptureDevice, which
        // can behave inconsistently for audio-only flows on some OS versions.
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
          DispatchQueue.main.async {
            result(granted)
          }
        }
      case "recordPermissionStatus":
        let status = AVAudioSession.sharedInstance().recordPermission
        switch status {
        case .undetermined:
          result("undetermined")
        case .denied:
          result("denied")
        case .granted:
          result("granted")
        @unknown default:
          result("undetermined")
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let voipMatrix = FlutterMethodChannel(
      name: AppDelegate.voipMatrixPusherChannelName,
      binaryMessenger: messenger
    )
    voipMatrixPusherChannel = voipMatrix
    voipMatrix.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: nil, details: nil))
        return
      }
      switch call.method {
      case "getSygnalVoipPushKey":
        let b64 =
          self.lastVoipTokenSygnalB64
          ?? UserDefaults.standard.string(forKey: kMatrixSygnalVoipPushKeyDefaultsKey)
        result(b64)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    if let b64 = lastVoipTokenSygnalB64
      ?? UserDefaults.standard.string(forKey: kMatrixSygnalVoipPushKeyDefaultsKey),
      !b64.isEmpty
    {
      voipMatrix.invokeMethod("onVoipTokenUpdated", arguments: b64)
    }
  }

  // MARK: - VoIP → CallKit (Sygnal / Matrix)

  /// Sygnal `ApnsPushkin` sets `aps.alert` to a localized alert dict with `loc-key` / `loc-args`.
  private static func apnsAlertLocKey(from dict: [String: Any]) -> String? {
    guard let aps = dict["aps"] as? [String: Any] else { return nil }
    if let alert = aps["alert"] as? [String: Any] {
      return alert["loc-key"] as? String ?? alert["loc_key"] as? String
    }
    return nil
  }

  /// Matrix message / invite pushes reuse the same VoIP topic on some setups; only real calls
  /// should hit CallKit. Mirrors Dart `_fcmDataLooksLikeRtcNotification` when `type` is present.
  private static func shouldPresentCallKitForVoipPayload(_ dict: [String: Any]) -> Bool {
    if let t = dict["type"] as? String, looksLikeRtcNotificationType(t) {
      return rtcNotificationIsRing(dict)
    }

    // Non-Sygnal backends: CallKit fields without `aps.alert.loc-key`.
    if dict["callkit"] is [String: Any] {
      return true
    }
    if apnsAlertLocKey(from: dict) == nil,
      dict["id"] != nil,
      let name = dict["nameCaller"] as? String,
      !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      return true
    }

    let locKey = apnsAlertLocKey(from: dict)

    // Sygnal legacy WebRTC `m.call.invite`.
    if locKey == "VOICE_CALL_FROM_USER" || locKey == "VIDEO_CALL_FROM_USER" {
      return true
    }

    // Sygnal maps unknown `n.type` (including `m.rtc.notification`) to `MSG_FROM_USER` with
    // `[sender]` — allow that for MatrixRTC; normal `m.room.message` uses longer loc-keys.
    if locKey == "MSG_FROM_USER" {
      return true
    }

    // Message-style and invite loc-keys must never wake CallKit.
    let denylistedLocKeys: Set<String> = [
      "MSG_FROM_USER_IN_ROOM",
      "MSG_FROM_USER_IN_ROOM_WITH_CONTENT",
      "MSG_FROM_USER_WITH_CONTENT",
      "IMAGE_FROM_USER",
      "IMAGE_FROM_USER_IN_ROOM",
      "ACTION_FROM_USER",
      "ACTION_FROM_USER_IN_ROOM",
      "USER_INVITE_TO_CHAT",
      "USER_INVITE_TO_NAMED_ROOM",
    ]
    if let locKey, denylistedLocKeys.contains(locKey) {
      return false
    }

    // Event-id-only sync payloads (no alert) or other non-call pushes: never CallKit.
    if locKey == nil || locKey?.isEmpty == true {
      return false
    }

    return false
  }

  private static func looksLikeRtcNotificationType(_ typeField: String) -> Bool {
    let t = typeField.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if t.isEmpty { return false }
    if t == "m.rtc.notification" { return true }
    if t.hasSuffix(".rtc.notification") { return true }
    if t.contains("msc4075.rtc.notification") { return true }
    return false
  }

  private static func rtcNotificationIsRing(_ dict: [String: Any]) -> Bool {
    if let flat = dict["content_notification_type"] as? String {
      let nt = flat.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if nt == "ring" { return true }
      if nt == "notification" { return false }
    }
    if let raw = dict["content"] as? String, !raw.isEmpty,
      let data = raw.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let nt = json["notification_type"] as? String
    {
      let v = nt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      if v == "ring" { return true }
      if v == "notification" { return false }
    }
    return true
  }

  // MARK: - PKPushRegistryDelegate

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    guard type == .voIP else { return }
    let tokenData = credentials.token
    let sygnalB64 = tokenData.base64EncodedString()
    lastVoipTokenSygnalB64 = sygnalB64
    UserDefaults.standard.set(sygnalB64, forKey: kMatrixSygnalVoipPushKeyDefaultsKey)

    // CallKit plugin historically uses a hex string for this device token.
    let hex = tokenData.map { String(format: "%02x", $0) }.joined()
    if let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance {
      plugin.setDevicePushTokenVoIP(hex)
    } else {
      // Plugin registers with the Flutter engine slightly later (implicit engine). Persist so
      // `getDevicePushTokenVoIP` still works once Dart listens.
      UserDefaults.standard.set(hex, forKey: kFlutterCallKitVoipTokenDefaultsKey)
    }

    DispatchQueue.main.async { [weak self] in
      self?.voipMatrixPusherChannel?.invokeMethod("onVoipTokenUpdated", arguments: sygnalB64)
    }
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    lastVoipTokenSygnalB64 = nil
    UserDefaults.standard.removeObject(forKey: kMatrixSygnalVoipPushKeyDefaultsKey)
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
    UserDefaults.standard.removeObject(forKey: kFlutterCallKitVoipTokenDefaultsKey)
    DispatchQueue.main.async { [weak self] in
      self?.voipMatrixPusherChannel?.invokeMethod("onVoipTokenInvalidated", arguments: nil)
    }
  }

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
    guard let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance else {
      NSLog("AppDelegate: VoIP push before CallKit plugin init; cannot report incoming call.")
      completion()
      return
    }

    let dict = payload.dictionaryPayload as? [String: Any] ?? [:]
    if !Self.shouldPresentCallKitForVoipPayload(dict) {
      NSLog(
        "AppDelegate: ignoring VoIP push for CallKit (not an incoming call payload); "
          + "aps.loc-key=\(Self.apnsAlertLocKey(from: dict) ?? "(nil)")"
      )
      completion()
      return
    }

    var args: [String: Any?] = [:]
    for (key, value) in payload.dictionaryPayload {
      guard let k = key as? String else { continue }
      args[k] = value
    }
    // Optional nested object from your push backend.
    if let nested = args["callkit"] as? [String: Any] {
      for (k, v) in nested {
        args[k] = v
      }
    }

    if (args["id"] as? String)?.isEmpty ?? true {
      args["id"] = UUID().uuidString
    }
    if (args["nameCaller"] as? String)?.isEmpty ?? true {
      args["nameCaller"] = "Incoming call"
    }
    if (args["handle"] as? String)?.isEmpty ?? true {
      args["handle"] = "matrix"
    }
    if args["type"] == nil {
      if let isVideo = args["isVideo"] as? Bool {
        args["type"] = isVideo ? 1 : 0
      } else if let n = args["isVideo"] as? Int {
        args["type"] = n != 0 ? 1 : 0
      }
    }

    let data = flutter_callkit_incoming.Data(args: args)
    plugin.showCallkitIncoming(data, fromPushKit: true, completion: completion)
  }

  /// Start call from Phone / Siri “recent” when the plugin encrypted the handle.
  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([any UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if let handleObj = userActivity.handle,
       let isVideo = userActivity.isVideo,
       let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance {
      let objData = handleObj.getDecryptHandle()
      let nameCaller = objData["nameCaller"] as? String ?? ""
      let handle = objData["handle"] as? String ?? ""
      let data = flutter_callkit_incoming.Data(
        id: UUID().uuidString,
        nameCaller: nameCaller,
        handle: handle,
        type: isVideo ? 1 : 0
      )
      plugin.startCall(data, fromPushKit: true)
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }
}
