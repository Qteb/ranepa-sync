import Flutter
import Foundation
import WatchConnectivity

/// Передаёт ближайшие пары на Apple Watch. Часы сами в ЛК не ходят:
/// после каждого обновления расписания iPhone отправляет им то же, что
/// получает виджет. Регистрируется и в основном движке, и в фоновом
/// (workmanager), поэтому сделан плагином.
final class WatchBridge: NSObject, FlutterPlugin, WCSessionDelegate {
  static let shared = WatchBridge()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ranepa/watch", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(shared, channel: channel)
    shared.activate()
  }

  private var pending: [String: Any]?

  func activate() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    if session.delegate == nil { session.delegate = self }
    if session.activationState != .activated { session.activate() }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "update", let args = call.arguments as? [String: Any],
          let lessons = args["lessons"] as? String
    else { return result(FlutterMethodNotImplemented) }
    send([
      "lessons": lessons,
      "nowShift": args["nowShift"] as? Double ?? 0,
      "sentAt": Date().timeIntervalSince1970,
    ])
    result(nil)
  }

  private func send(_ context: [String: Any]) {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated else {
      pending = context
      return activate()
    }
    guard session.isPaired, session.isWatchAppInstalled else { return }
    try? session.updateApplicationContext(context)
    // Усложнение на циферблате: так часы обновят его сразу, а не при
    // следующем открытии приложения. У системы на это дневной лимит.
    if session.isComplicationEnabled, session.remainingComplicationUserInfoTransfers > 0 {
      session.transferCurrentComplicationUserInfo(context)
    }
  }

  func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
    guard state == .activated, let context = pending else { return }
    pending = nil
    send(context)
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  // Пользователь сменил часы — активируем сессию для новых.
  func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
