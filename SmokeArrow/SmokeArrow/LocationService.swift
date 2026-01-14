import Combine
import CoreLocation
import Foundation

@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var location: CLLocation?
    @Published private(set) var heading: CLHeading?
    @Published private(set) var lastError: Error?

    private let manager: CLLocationManager
    private var didStart = false

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()

        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.headingFilter = 1
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        default:
            return false
        }
    }

    func start() {
        didStart = true
        refreshAuthorizationStatus()
        startIfPossible()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func requestAuthorizationIfNeeded() {
        refreshAuthorizationStatus()
        guard authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func refreshAuthorizationStatus() {
        let current = manager.authorizationStatus
        if authorizationStatus != current {
            authorizationStatus = current
        }
    }

    var bestHeadingDegrees: CLLocationDirection? {
        if let heading, heading.headingAccuracy >= 0 {
            if heading.trueHeading >= 0 {
                return heading.trueHeading
            }
            return heading.magneticHeading
        }

        if let course = location?.course, course >= 0 {
            return course
        }

        return nil
    }

    private func startIfPossible() {
        lastError = nil
        let status = manager.authorizationStatus
        if authorizationStatus != status {
            authorizationStatus = status
        }

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() {
                manager.startUpdatingHeading()
            }
        case .notDetermined:
            break
        default:
            break
        }
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            guard didStart else { return }
            startIfPossible()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            location = latest
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            heading = newHeading
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error
            if let clError = error as? CLError, clError.code == .denied {
                authorizationStatus = manager.authorizationStatus
                stop()
            }
        }
    }
}
