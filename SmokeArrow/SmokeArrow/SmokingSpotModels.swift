import CoreLocation
import Foundation

enum SmokeModel {
    struct Coordinate: Hashable, Sendable {
        let latitude: Double
        let longitude: Double

        var clCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    enum SpotCategory: String, Sendable {
        case smokingSpot
        case cafe
    }

    enum SearchMode: Equatable, Sendable {
        case smokingOnly
        case includeCafe
    }

    struct Spot: Equatable, Identifiable, Sendable {
        let name: String?
        let coordinate: Coordinate
        let category: SpotCategory

        var id: String {
            let lat = Int((coordinate.latitude * 100_000).rounded())
            let lon = Int((coordinate.longitude * 100_000).rounded())
            return "\(name ?? "")|\(lat)|\(lon)"
        }

        func distance(from location: CLLocation) -> CLLocationDistance {
            CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude).distance(from: location)
        }
    }
}
