import CoreLocation
import Foundation

enum DistanceDisplayFormatter {
    enum DistanceZone: Equatable {
        case unknown
        case near
        case walkable
        case hesitant
        case far
        case outOfRange
        case outOfRangeLong
    }

    struct Presentation: Equatable {
        let zone: DistanceZone
        let text: String
    }

    static func presentation(fromMeters meters: CLLocationDistance) -> Presentation {
        guard meters.isFinite, meters >= 0 else {
            return Presentation(zone: .unknown, text: "--")
        }

        switch meters {
        case ..<150:
            return Presentation(zone: .near, text: "すぐ近く")
        case 150..<400:
            return Presentation(zone: .walkable, text: "徒歩圏内")
        case 400..<600:
            return Presentation(zone: .hesitant, text: "少し遠い")
        case 600..<800:
            return Presentation(zone: .far, text: "かなり遠い")
        case 800..<1000:
            return Presentation(zone: .outOfRange, text: "徒歩圏外")
        default:
            return Presentation(zone: .outOfRangeLong, text: "徒歩圏外")
        }
    }

    static func string(fromMeters meters: CLLocationDistance) -> String {
        presentation(fromMeters: meters).text
    }

    static func detailText(fromMeters meters: CLLocationDistance) -> String {
        guard meters.isFinite, meters >= 0 else { return "--" }
        if meters < 1000 {
            return "\(Int(meters.rounded()))m"
        }
        let km = meters / 1000
        if km < 10 {
            return String(format: "%.1fkm", km)
        }
        return String(format: "%.0fkm", km)
    }
}
