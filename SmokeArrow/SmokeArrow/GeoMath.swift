import Foundation

enum GeoMath {
    static func bearingDegrees(from: SmokeModel.Coordinate, to: SmokeModel.Coordinate) -> Double {
        let lat1 = degreesToRadians(from.latitude)
        let lon1 = degreesToRadians(from.longitude)
        let lat2 = degreesToRadians(to.latitude)
        let lon2 = degreesToRadians(to.longitude)

        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radians = atan2(y, x)
        let degrees = radiansToDegrees(radians)
        return normalize360(degrees)
    }

    static func normalize360(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d
    }

    static func normalize180(_ degrees: Double) -> Double {
        var d = normalize360(degrees)
        if d > 180 { d -= 360 }
        return d
    }

    static func smoothAngleDegrees(previous: Double?, next: Double, deltaTime: TimeInterval, smoothingTime: TimeInterval) -> Double {
        guard let previous else { return normalize180(next) }
        guard deltaTime > 0, smoothingTime > 0 else { return normalize180(next) }
        let alpha = 1 - exp(-deltaTime / smoothingTime)
        let delta = normalize180(next - previous)
        return normalize180(previous + (delta * alpha))
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }

    private static func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180 / .pi
    }
}
