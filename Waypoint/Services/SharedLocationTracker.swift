import CoreLocation
import Combine

@MainActor final class SharedLocationTracker: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var status = "Location sharing is off"
    @Published var coordinate: SelectedCoordinate?
    private let manager = CLLocationManager()
    private var enabled = false
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        if !value { manager.stopUpdatingLocation(); coordinate = nil; status = "Location sharing is off"; return }
        if manager.authorizationStatus == .notDetermined { status = "Allow Location access when prompted to publish your pin"; manager.requestWhenInUseAuthorization() }
        else if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { status = "Finding your device location…"; manager.startUpdatingLocation(); manager.requestLocation() }
        else { manager.stopUpdatingLocation(); coordinate = nil; status = "Location access is denied. Enable it in Settings, or start a spoof to share its position." }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { if enabled { setEnabled(true) } }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard enabled, let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) < 60 else { return }
        coordinate = SelectedCoordinate(location.coordinate)
        status = "Device location available"
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { coordinate = nil; status = "Device location is unavailable. Check Location Services or start a spoof." }
}
