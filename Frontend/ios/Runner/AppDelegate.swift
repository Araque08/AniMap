import Flutter
import CoreLocation
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  CLLocationManagerDelegate
{
  private let locationManager = CLLocationManager()
  private var pendingLocationResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyBest

    let locationChannel = FlutterMethodChannel(
      name: "animap/location",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    locationChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getCurrentLocation" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.requestCurrentLocation(result)
    }
  }

  private func requestCurrentLocation(_ result: @escaping FlutterResult) {
    guard pendingLocationResult == nil else {
      result(FlutterError(
        code: "LOCATION_BUSY",
        message: "Ya hay una solicitud de ubicación en curso",
        details: nil
      ))
      return
    }
    guard CLLocationManager.locationServicesEnabled() else {
      result(FlutterError(
        code: "LOCATION_DISABLED",
        message: "Activa la ubicación del dispositivo",
        details: nil
      ))
      return
    }

    pendingLocationResult = result
    switch locationManager.authorizationStatus {
    case .notDetermined:
      locationManager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      locationManager.requestLocation()
    default:
      finishLocationWithError(
        code: "LOCATION_PERMISSION",
        message: "Permiso de ubicación denegado"
      )
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    handleLocationAuthorizationChange(manager)
  }

  func locationManager(
    _ manager: CLLocationManager,
    didChangeAuthorization status: CLAuthorizationStatus
  ) {
    if #available(iOS 14.0, *) { return }
    handleLocationAuthorizationChange(manager)
  }

  private func handleLocationAuthorizationChange(_ manager: CLLocationManager) {
    guard pendingLocationResult != nil else { return }
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse:
      manager.requestLocation()
    case .denied, .restricted:
      finishLocationWithError(
        code: "LOCATION_PERMISSION",
        message: "Permiso de ubicación denegado"
      )
    default:
      break
    }
  }

  func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    guard let location = locations.last else {
      finishLocationWithError(
        code: "LOCATION_UNAVAILABLE",
        message: "El dispositivo no devolvió una ubicación válida"
      )
      return
    }
    pendingLocationResult?([
      "latitude": location.coordinate.latitude,
      "longitude": location.coordinate.longitude,
      "accuracy": location.horizontalAccuracy,
    ])
    pendingLocationResult = nil
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    finishLocationWithError(
      code: "LOCATION_UNAVAILABLE",
      message: "No fue posible obtener la ubicación GPS"
    )
  }

  private func finishLocationWithError(code: String, message: String) {
    pendingLocationResult?(FlutterError(code: code, message: message, details: nil))
    pendingLocationResult = nil
  }
}
