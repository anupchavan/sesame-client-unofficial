import Foundation
import CoreLocation

/// One-shot Mac location + reverse-geocoded address, mirroring what the iPhone app puts in
/// `location_state`. Cached; refreshed on demand. Location is only ever sent to the agent as
/// context — never elsewhere.
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    struct Fix: Equatable { var latitude: Double; var longitude: Double; var address: String }
    @Published private(set) var fix: Fix?

    /// Called when a fresh fix (or geocoded address) arrives, so clients can re-push it.
    var onUpdate: (() -> Void)?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        default:
            break // denied/restricted — silently skip location
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .authorized || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
            self.fix = Fix(latitude: lat, longitude: lon, address: self.fix?.address ?? "")
            self.onUpdate?()
            if let places = try? await self.geocoder.reverseGeocodeLocation(loc), let p = places.first {
                let addr = [p.name, p.subLocality, p.locality, p.administrativeArea, p.postalCode, p.country]
                    .compactMap { $0 }
                    .reduce(into: [String]()) { acc, s in if !acc.contains(s) { acc.append(s) } }
                    .joined(separator: ", ")
                if !addr.isEmpty {
                    self.fix = Fix(latitude: lat, longitude: lon, address: addr)
                    self.onUpdate?()
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
