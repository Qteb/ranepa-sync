import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Фоновое обновление расписания: свой Flutter-движок с теми же плагинами
    // (WebView, уведомления, виджет). Идентификатор — как в Info.plist
    // и lib/services/background.dart.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
      WatchBridge.register(with: registry.registrar(forPlugin: "WatchBridge")!)
      LiveActivityBridge.register(with: registry.registrar(forPlugin: "LiveActivityBridge")!)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.qteb.ranepaTimetable.refresh",
      earliestBeginInSeconds: NSNumber(value: 4 * 60 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    WatchBridge.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "WatchBridge")!)
    LiveActivityBridge.register(with: engineBridge.pluginRegistry.registrar(forPlugin: "LiveActivityBridge")!)
  }
}
