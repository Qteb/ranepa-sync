import ActivityKit
import Flutter
import UIKit

/// Пара на экране блокировки и в Dynamic Island. Flutter присылает
/// оставшиеся сегодня пары после каждого обновления и при открытии
/// приложения. Запустить активность iOS разрешает только из открытого
/// приложения, обновлять и завершать — и из фона.
final class LiveActivityBridge: NSObject, FlutterPlugin {
  static let shared = LiveActivityBridge()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "ranepa/live", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(shared, channel: channel)
  }

  private struct Item: Decodable {
    let s: Double
    let e: Double
    let t: String
    let k: String
    let r: String
    let R: String
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "update", let args = call.arguments as? [String: Any] else {
      return result(FlutterMethodNotImplemented)
    }
    let enabled = args["enabled"] as? Bool ?? false
    let raw = (args["lessons"] as? String)?.data(using: .utf8) ?? Data()
    let items = (try? JSONDecoder().decode([Item].self, from: raw)) ?? []
    guard #available(iOS 16.2, *) else { return result(nil) }
    Task {
      await apply(items: enabled ? items : [])
      result(nil)
    }
  }

  @available(iOS 16.2, *)
  private func apply(items: [Item]) async {
    typealias A = LessonActivityAttributes
    let now = Date()
    let lessons = items
      .map { A.Lesson(title: $0.t, kind: $0.k, room: $0.r, fullRoom: $0.R,
                      start: Date(timeIntervalSince1970: $0.s), end: Date(timeIntervalSince1970: $0.e)) }
      .filter { $0.end > now }
      .sorted { $0.start < $1.start }
    let running = Activity<A>.activities

    guard let first = lessons.first else {
      for a in running { await a.end(nil, dismissalPolicy: .immediate) }
      return
    }
    let state = A.ContentState(lesson: first, next: lessons.dropFirst().first, isCurrent: first.start <= now)
    // Когда пара закончится, расширение покажет перемену или «пары
    // закончились», даже если приложение не успеет обновить активность.
    let stale = first.start > now ? first.start : first.end
    let content = ActivityContent(state: state, staleDate: stale)

    if let current = running.first {
      await current.update(content)
      for extra in running.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
      return
    }
    let active = await MainActor.run { UIApplication.shared.applicationState == .active }
    guard active, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    _ = try? Activity<A>.request(attributes: A(), content: content)
  }
}
