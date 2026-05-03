import AVFoundation
import CallKit
import Flutter
import PushKit
import UIKit
import UserNotifications
import flutter_callkit_incoming

// MARK: - PushKit / CallKit (iOS 13+)
//
// Apple requires that every VoIP push result in a CallKit `reportNewIncomingCall` before the
// PushKit `completion` handler runs. Calling `completion()` alone for “message” payloads on
// the VoIP channel causes SIGABRT (see PushKit in crash stack).

/// When `SwiftFlutterCallkitIncomingPlugin` is not ready yet, VoIP pushes still must hit CallKit.
private final class VoipPushCallKitPolicyFallback: NSObject, CXProviderDelegate {
  static let shared = VoipPushCallKitPolicyFallback()
  private var provider: CXProvider?
  private let lock = NSLock()

  func reportIncomingThenComplete(completion: @escaping () -> Void) {
    lock.lock()
    defer { lock.unlock() }
    let localizedName =
      (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
      ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
      ?? "App"
    let config = CXProviderConfiguration(localizedName: localizedName)
    config.supportsVideo = false
    config.maximumCallsPerCallGroup = 1
    config.includesCallsInRecents = false
    if provider == nil {
      let p = CXProvider(configuration: config)
      p.setDelegate(self, queue: nil)
      provider = p
    }
    guard let provider else {
      completion()
      return
    }
    let uuid = UUID()
    let update = CXCallUpdate()
    update.hasVideo = false
    update.localizedCallerName = localizedName
    update.remoteHandle = CXHandle(type: .generic, value: "message")
    provider.reportNewIncomingCall(with: uuid, update: update) { _ in
      provider.reportCall(with: uuid, endedAt: Date(), reason: .failed)
      completion()
    }
  }

  func providerDidReset(_: CXProvider) {}
}

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

    application.registerForRemoteNotifications()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Register PushKit only after plugins load so `SwiftFlutterCallkitIncomingPlugin.sharedInstance`
    // exists before any VoIP payload is handled (see PUSHKIT.md in flutter_callkit_incoming).
    if voipRegistry == nil {
      let registry = PKPushRegistry(queue: DispatchQueue.main)
      registry.delegate = self
      registry.desiredPushTypes = [PKPushType.voIP]
      voipRegistry = registry
    }
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

  /// Matrix event type hint on the push root (Sygnal often omits `type`; see `shouldPresentCallKitForVoipPayload`).
  private static func resolvedMatrixEventTypeField(from dict: [String: Any]) -> String? {
    for key in ["type", "content_type", "content_msgtype"] {
      guard let t = dict[key] as? String else { continue }
      let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
      if !s.isEmpty { return s }
    }
    return nil
  }

  /// Matrix message / invite pushes reuse the same VoIP topic on some setups; only real calls
  /// should hit CallKit. Mirrors Dart `_fcmDataLooksLikeRtcNotification` when a type field is present.
  private static func shouldPresentCallKitForVoipPayload(_ dict: [String: Any]) -> Bool {
    if let t = resolvedMatrixEventTypeField(from: dict), looksLikeRtcNotificationType(t) {
      return rtcNotificationIsRing(dict)
    }

    // Non-Sygnal backends: explicit CallKit object on the push root.
    if dict["callkit"] is [String: Any] {
      return true
    }

    let locKey = apnsAlertLocKey(from: dict)

    // Sygnal legacy WebRTC `m.call.invite`.
    if locKey == "VOICE_CALL_FROM_USER" || locKey == "VIDEO_CALL_FROM_USER" {
      return true
    }

    // Sygnal `ApnsPushkin` uses `MSG_FROM_USER` for *any* unknown `n.type` **and** for minimal
    // `m.room.message` / `m.room.encrypted` (no room display + no body extract). It does not put
    // `type` on the wire by default, so this loc-key is not a reliable “incoming call” signal.

    // Message-style and invite loc-keys must never wake CallKit.
    let denylistedLocKeys: Set<String> = [
      "MSG_FROM_USER",
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

  /// Same window as Rust `RTC_INCOMING_RING_NOTIFY_MAX_AGE_MS` (120s).
  private static let voipRtcRingMaxAgeMs: UInt64 = 120_000

  private static func isMatrixRtcRingVoipPayload(_ dict: [String: Any]) -> Bool {
    guard let t = resolvedMatrixEventTypeField(from: dict), looksLikeRtcNotificationType(t) else {
      return false
    }
    return rtcNotificationIsRing(dict)
  }

  private static func voipPushOriginServerTsMs(_ dict: [String: Any]) -> UInt64? {
    let keys = ["origin_server_ts", "event_ts", "event_origin_server_ts", "server_ts", "ts"]
    for k in keys {
      if let s = dict[k] as? String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let v = UInt64(t) { return v }
      }
      if let n = dict[k] as? NSNumber {
        return n.uint64Value
      }
      if let i = dict[k] as? Int {
        return UInt64(i)
      }
      if let i = dict[k] as? Int64 {
        return UInt64(i)
      }
    }
    return nil
  }

  private static func voipRtcRingPayloadIsStale(_ dict: [String: Any]) -> Bool {
    guard isMatrixRtcRingVoipPayload(dict) else { return false }
    guard let ts = voipPushOriginServerTsMs(dict) else { return false }
    let nowMs = UInt64(Date().timeIntervalSince1970 * 1_000)
    if ts == 0 { return true }
    return nowMs > ts && nowMs - ts > voipRtcRingMaxAgeMs
  }

  private static func missedCallTitleFromVoipPayload(_ dict: [String: Any]) -> String {
    if let s = dict["room_name"] as? String {
      let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if !t.isEmpty { return t }
    }
    if let s = dict["sender_display_name"] as? String {
      let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
      if !t.isEmpty { return t }
    }
    return (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      ?? "Matrix"
  }

  private static func scheduleLocalMissedCallNotificationFromVoipPayload(_ dict: [String: Any]) {
    let caller =
      (dict["sender_display_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? (dict["sender"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      ?? ""
    let content = UNMutableNotificationContent()
    content.title = missedCallTitleFromVoipPayload(dict)
    content.body = caller.isEmpty ? "Missed call" : "Missed call from \(caller)"
    content.sound = .default
    let rawEventId =
      (dict["event_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let reqId =
      rawEventId.isEmpty
      ? "matrix_missed_voip:\(UUID().uuidString)"
      : "matrix_missed_voip:\(rawEventId)"
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
    let request = UNNotificationRequest(identifier: reqId, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request) { error in
      if let error {
        NSLog("AppDelegate: missed-call local notification failed: \(error)")
      }
    }
  }

  /// Sygnal may deliver room-message pushes on the VoIP Matrix pusher. iOS still requires
  /// CallKit `reportNewIncomingCall` for those pushes; use a minimal call the plugin ends
  /// immediately (no missed-call UI). Prefer routing messages to the non-VoIP pusher on the server.
  private static func callKitArgsForNonCallVoipCompliancePush() -> [String: Any?] {
    let appName =
      (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
      ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)?.trimmingCharacters(
        in: .whitespacesAndNewlines)
      ?? "App"
    return [
      "id": UUID().uuidString,
      "nameCaller": appName,
      "handle": "message",
      "type": 0,
      "duration": 1,
      "extra": ["matrixVoipPushCompliance": true] as NSDictionary,
      "missedCallNotification": [
        "showNotification": false,
        "isShowCallback": false,
      ] as [String: Any],
      "ios": [
        "includesCallsInRecents": false,
        "configureAudioSession": false,
        "audioSessionActive": false,
      ] as [String: Any],
    ]
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
      NSLog(
        "AppDelegate: VoIP push before CallKit plugin init; retrying next run loop (PushKit policy)."
      )
      DispatchQueue.main.async {
        if let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance {
          Self.deliverVoipPushToCallKit(
            payload: payload,
            plugin: plugin,
            completion: completion
          )
        } else {
          NSLog(
            "AppDelegate: CallKit plugin still nil after deferral; using CXProvider fallback for PushKit policy."
          )
          VoipPushCallKitPolicyFallback.shared.reportIncomingThenComplete(completion: completion)
        }
      }
      return
    }

    Self.deliverVoipPushToCallKit(
      payload: payload,
      plugin: plugin,
      completion: completion
    )
  }

  private static func deliverVoipPushToCallKit(
    payload: PKPushPayload,
    plugin: SwiftFlutterCallkitIncomingPlugin,
    completion: @escaping () -> Void
  ) {
    let dict = payload.dictionaryPayload as? [String: Any] ?? [:]
    if voipRtcRingPayloadIsStale(dict) {
      NSLog(
        "AppDelegate: stale MatrixRTC VoIP ring (origin ts); posting missed-call notification + "
          + "minimal CallKit for PushKit policy."
      )
      scheduleLocalMissedCallNotificationFromVoipPayload(dict)
      let data = flutter_callkit_incoming.Data(args: callKitArgsForNonCallVoipCompliancePush())
      plugin.showCallkitIncoming(data, fromPushKit: true, completion: completion)
      return
    }
    if !shouldPresentCallKitForVoipPayload(dict) {
      NSLog(
        "AppDelegate: VoIP push is not a MatrixRTC ring; reporting minimal CallKit per PushKit policy "
          + "(aps.loc-key=\(apnsAlertLocKey(from: dict) ?? "(nil)")). "
          + "Prefer non-VoIP pusher for messages."
      )
      let data = flutter_callkit_incoming.Data(args: callKitArgsForNonCallVoipCompliancePush())
      plugin.showCallkitIncoming(data, fromPushKit: true, completion: completion)
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

    // Matrix → Dart expects `extra.roomId` / `extra.rtcEventId` (see [showMatrixIncomingCallKit]).
    // Sygnal VoIP payloads often put `room_id` / `event_id` on the push root instead.
    func pickRootString(_ keys: [String]) -> String {
      for k in keys {
        guard let s = args[k] as? String else { continue }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
      }
      return ""
    }
    var extra = (args["extra"] as? [String: Any]) ?? [:]
    let roomFromRoot = pickRootString(["room_id", "roomId"])
    let rtcFromRoot = pickRootString(["event_id", "eventId", "rtcEventId"])
    let nameFromRoot = pickRootString(["room_name", "roomName"])
    let existingRoom =
      (extra["roomId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let existingRtc =
      (extra["rtcEventId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let existingName =
      (extra["roomName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if existingRoom.isEmpty, !roomFromRoot.isEmpty {
      extra["roomId"] = roomFromRoot
    }
    if existingRtc.isEmpty, !rtcFromRoot.isEmpty {
      extra["rtcEventId"] = rtcFromRoot
    }
    if existingName.isEmpty, !nameFromRoot.isEmpty {
      extra["roomName"] = nameFromRoot
    }
    if !extra.isEmpty {
      args["extra"] = extra
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
