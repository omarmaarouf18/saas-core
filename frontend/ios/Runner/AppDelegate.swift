import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let rawKey = Bundle.main.object(forInfoDictionaryKey: "MAPS_API_KEY") as? String {
      let apiKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
      if !apiKey.isEmpty && !apiKey.hasPrefix("$(") {
        GMSServices.provideAPIKey(apiKey)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
