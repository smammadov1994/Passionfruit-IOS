import CoreLocation
import Foundation

struct ResolvedLocation: Sendable, Equatable {
    var lat: Double
    var lng: Double
    /// Reverse-geocoded city. Empty when the geocoder had no answer.
    var city: String
}

/// One-shot, when-in-use location with a reverse-geocoded city.
@MainActor
protocol LocationService: AnyObject {
    var status: PermissionStatus { get }
    /// Asks for permission when needed, takes one fix and resolves the city.
    /// Throws `TempoError.permissionDenied(.location)` when access is off.
    func currentLocation() async throws -> ResolvedLocation
}

@MainActor
final class LiveLocationService: NSObject, LocationService {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationFix, Error>?

    private struct LocationFix: Sendable {
        var lat: Double
        var lng: Double
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var status: PermissionStatus {
        LiveLocationService.map(manager.authorizationStatus)
    }

    func currentLocation() async throws -> ResolvedLocation {
        let current: PermissionStatus = status
        if current == .denied {
            throw TempoError.permissionDenied(.location)
        }
        if continuation != nil {
            throw TempoError.unknown(String(localized: "Still finding your location. Give it a second."))
        }
        let fix: LocationFix = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LocationFix, Error>) in
            self.continuation = continuation
            if current == .notDetermined {
                self.manager.requestWhenInUseAuthorization()
            } else {
                self.manager.requestLocation()
            }
        }
        let city: String = await LiveLocationService.city(lat: fix.lat, lng: fix.lng)
        return ResolvedLocation(lat: fix.lat, lng: fix.lng, city: city)
    }

    private static func city(lat: Double, lng: Double) async -> String {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: lat, longitude: lng)
        guard let placemarks = try? await geocoder.reverseGeocodeLocation(location) else {
            return ""
        }
        guard let placemark = placemarks.first else {
            return ""
        }
        return placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea ?? ""
    }

    private static func map(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    private func authorizationChanged() {
        guard continuation != nil else { return }
        switch status {
        case .granted:
            manager.requestLocation()
        case .denied:
            finish(.failure(TempoError.permissionDenied(.location)))
        case .notDetermined:
            break
        }
    }

    private func finish(_ result: Result<LocationFix, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let fix):
            continuation.resume(returning: fix)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

extension LiveLocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationChanged()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let lat: Double = last.coordinate.latitude
        let lng: Double = last.coordinate.longitude
        Task { @MainActor in
            self.finish(.success(LocationFix(lat: lat, lng: lng)))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.finish(.failure(TempoError.unknown(String(localized: "Couldn't find your location. You can type your city instead."))))
        }
    }
}

/// Demo-mode location: midtown Manhattan, no prompt.
@MainActor
final class MockLocationService: LocationService {
    var status: PermissionStatus = .granted
    var location: ResolvedLocation = ResolvedLocation(lat: 40.7549, lng: -73.9840, city: "New York")

    init() {}

    func currentLocation() async throws -> ResolvedLocation {
        if status == .denied {
            throw TempoError.permissionDenied(.location)
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        return location
    }
}
