import CoreLocation
import Foundation

@MainActor
final class LocationContextService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = LocationContextService()
    @Published private(set) var authorization = CLAuthorizationStatus.notDetermined
    @Published private(set) var location: CLLocation?
    @Published var rawRouteOptIn = false

    private let manager = CLLocationManager()
    private var route: [[String: Double]] = []
    private var pendingOneShot = false
    private var trackingKind: String?
    private var lastRoutePersist = Date.distantPast

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
        manager.pausesLocationUpdatesAutomatically = true
        #if os(iOS)
        manager.activityType = .fitness
        manager.allowsBackgroundLocationUpdates = false
        #endif
        authorization = manager.authorizationStatus
    }

    func requestOneShot() {
        pendingOneShot = true
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized(manager.authorizationStatus) {
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.requestLocation()
            pendingOneShot = false
        }
    }

    func startTracking(kind: String) {
        guard Self.outdoorKinds.contains(kind) else {
            stopTracking()
            return
        }
        trackingKind = kind
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        guard isAuthorized(manager.authorizationStatus) else { return }
        // Personalization needs context, not a route. A single coarse fix avoids
        // keeping GPS hardware awake unless the user explicitly records a route.
        guard rawRouteOptIn else {
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            manager.distanceFilter = kCLDistanceFilterNone
            manager.requestLocation()
            trackingKind = nil
            return
        }
        configureTracking(for: kind)
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        if rawRouteOptIn { persistRoute() }
        trackingKind = nil
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 100
    }

    func nearestPlace(in places: [Place]) -> Place? {
        guard let location else { return nil }
        return places.compactMap { place -> (Place, CLLocationDistance)? in
            guard place.privacy == "location", let latitude = Double(place.latitude),
                  let longitude = Double(place.longitude) else { return nil }
            let distance = location.distance(from: CLLocation(latitude: latitude, longitude: longitude))
            return distance <= Double(place.radiusM) ? (place, distance) : nil
        }.min(by: { $0.1 < $1.1 })?.0
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if isAuthorized(authorization) {
            if let trackingKind {
                if rawRouteOptIn {
                    configureTracking(for: trackingKind)
                    manager.startUpdatingLocation()
                } else {
                    manager.desiredAccuracy = kCLLocationAccuracyKilometer
                    manager.distanceFilter = kCLDistanceFilterNone
                    manager.requestLocation()
                    self.trackingKind = nil
                }
            } else if pendingOneShot {
                manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                manager.requestLocation()
                pendingOneShot = false
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        location = latest
        guard rawRouteOptIn else { return }
        route.append([
            "latitude": latest.coordinate.latitude, "longitude": latest.coordinate.longitude,
            "timestamp": latest.timestamp.timeIntervalSince1970,
        ])
        if route.count.isMultiple(of: 5) || Date().timeIntervalSince(lastRoutePersist) >= 60 {
            persistRoute()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func eraseRecordedRoute() {
        route = []
        try? FileManager.default.removeItem(at: routeURL)
    }

    var authorizationLabel: String {
        if isAuthorized(authorization) { return "Allowed" }
        if authorization == .denied || authorization == .restricted { return "Manual only" }
        return "Not requested"
    }

    private func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        #if os(iOS)
        status == .authorizedAlways || status == .authorizedWhenInUse
        #else
        status == .authorizedAlways
        #endif
    }

    private var routeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "uMusic/private-workout-route.json")
    }

    private func persistRoute() {
        guard rawRouteOptIn else { return }
        try? FileManager.default.createDirectory(
            at: routeURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? JSONSerialization.data(withJSONObject: route).write(to: routeURL, options: .atomic)
        lastRoutePersist = Date()
    }

    private func configureTracking(for kind: String) {
        if AppEnergyPolicy.lowEnergyEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled {
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            manager.distanceFilter = 500
        } else {
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = kind == "cycling" ? 250 : 100
        }
    }

    private static let outdoorKinds: Set<String> = ["cycling", "running", "walking"]
}
