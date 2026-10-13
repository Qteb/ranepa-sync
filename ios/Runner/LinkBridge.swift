import Flutter
import UIKit

/// Ссылки ranepa://lesson?start=… из Live Activity и виджета: открыть
/// приложение на этой паре. Приложение работает со сценами, поэтому
/// ссылки приходят через scene-делегата, в том числе при холодном старте.
final class LinkBridge: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  static let shared = LinkBridge()

  private var channel: FlutterMethodChannel?
  /// Ссылка, пришедшая до того, как Flutter спросил о ней.
  private var pending: String?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ranepa/links", binaryMessenger: registrar.messenger())
    shared.channel = channel
    registrar.addMethodCallDelegate(shared, channel: channel)
    registrar.addSceneDelegate(shared)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "initial" else { return result(FlutterMethodNotImplemented) }
    result(pending)
    pending = nil
  }

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
             options connectionOptions: UIScene.ConnectionOptions?) -> Bool {
    guard let url = connectionOptions?.urlContexts.first?.url, url.scheme == "ranepa" else { return false }
    pending = url.absoluteString
    return true
  }

  func scene(_ scene: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) -> Bool {
    guard let url = contexts.first?.url, url.scheme == "ranepa" else { return false }
    channel?.invokeMethod("open", arguments: url.absoluteString)
    return true
  }
}
