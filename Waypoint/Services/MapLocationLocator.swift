import CoreLocation
import Combine

/// One-shot location for the recenter button. This service never uploads location.
@MainActor final class MapLocationLocator: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var coordinate: SelectedCoordinate?
    @Published var locating = false
    @Published var message: String?
    private let manager = CLLocationManager()
    private var deadline: Task<Void, Never>?
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }
    func locate() {
        guard !locating else { return }
        coordinate = nil; message = nil; locating = true
        requestIfAuthorized()
        deadline = Task {
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            if locating { fail("Could not find a current location. Try again outdoors or check Location Services.") }
        }
    }
    private func requestIfAuthorized() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: fail("Allow Location access for Roam Control in Settings to center on your device location. An active spoof can still be centered without it.")
        @unknown default: fail("Location Services are unavailable.")
        }
    }
    func cancel() { deadline?.cancel(); deadline = nil; locating = false }
    private func fail(_ text: String) { cancel(); message = text }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if locating { requestIfAuthorized() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locating, let point = locations.last, point.horizontalAccuracy >= 0,
              abs(point.timestamp.timeIntervalSinceNow) < 30 else { return }
        cancel(); coordinate = SelectedCoordinate(point.coordinate)
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard locating else { return }
        fail("Could not find your location. Check Location Services and try again.")
    }
}
