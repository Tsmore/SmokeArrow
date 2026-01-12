import CoreLocation
import Foundation
import MapKit

enum SmokingSpotSearchError: Error {
    case timedOut
    case failed
}

final class SmokingSpotSearchService {
    struct Config {
        var radiiMeters: [CLLocationDistance] = [1_000, 2_000, 5_000]
        var stepTimeoutSeconds: TimeInterval = 2
        var cacheTTLSeconds: TimeInterval = 5 * 60
        var smokingSpotQueries: [String] = ["喫煙所", "smoking area"]
        var cafeQueries: [String] = ["喫煙可能なカフェ", "喫煙可能 カフェ", "喫煙 カフェ", "smoking cafe"]
    }

    private struct Cache {
        let createdAt: Date
        let center: CLLocation
        let spots: [SmokeModel.Spot]
        let queriesKey: String
    }

    private struct SearchQuery: Sendable {
        let text: String
        let category: SmokeModel.SpotCategory
    }

    private let config: Config
    private var cache: Cache?

    init(config: Config = .init()) {
        self.config = config
    }

    func searchNearestSpots(
        from location: CLLocation,
        mode: SmokeModel.SearchMode = .smokingOnly,
        preference: SmokeModel.SpotCategory = .smokingSpot
    ) async throws -> [SmokeModel.Spot] {
        let queriesKey = queriesKey(for: mode, preference: preference)
        do {
            let activeQueries: [SearchQuery] = switch mode {
            case .smokingOnly:
                queries(for: .smokingSpot)
            case .includeCafe:
                queries(for: .smokingSpot) + queries(for: .cafe)
            }
            let spots = try await searchFirstAvailable(location: location, queries: activeQueries)
            cache = Cache(createdAt: Date(), center: location, spots: spots, queriesKey: queriesKey)
            return spots
        } catch {
            if
                let cache,
                cache.queriesKey == queriesKey,
                Date().timeIntervalSince(cache.createdAt) <= config.cacheTTLSeconds
            {
                return cache.spots
            }
            throw error
        }
    }

    private struct QueryOutcome: Sendable {
        let spots: [SmokeModel.Spot]
        let hadNonTimeoutError: Bool
    }

    private func searchWithinRadius(
        location: CLLocation,
        radius: CLLocationDistance,
        queries: [SearchQuery]
    ) async throws -> [SmokeModel.Spot] {
        let center = SmokeModel.Coordinate(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        let stepTimeoutSeconds = config.stepTimeoutSeconds

        let outcome = await withTaskGroup(of: QueryOutcome.self) { group in
            for query in queries {
                group.addTask {
                    do {
                        let spots = try await Self.search(
                            query: query.text,
                            center: center,
                            radius: radius,
                            timeoutSeconds: stepTimeoutSeconds,
                            category: query.category
                        )
                        return QueryOutcome(spots: spots, hadNonTimeoutError: false)
                    } catch is SmokingSpotSearchError {
                        return QueryOutcome(spots: [], hadNonTimeoutError: false)
                    } catch is CancellationError {
                        return QueryOutcome(spots: [], hadNonTimeoutError: false)
                    } catch {
                        return QueryOutcome(spots: [], hadNonTimeoutError: true)
                    }
                }
            }

            var merged: [SmokeModel.Spot] = []
            var hadNonTimeoutError = false
            for await item in group {
                merged.append(contentsOf: item.spots)
                hadNonTimeoutError = hadNonTimeoutError || item.hadNonTimeoutError
            }

            return QueryOutcome(spots: merged, hadNonTimeoutError: hadNonTimeoutError)
        }

        let deduped = Dictionary(grouping: outcome.spots, by: { $0.id }).compactMap { _, value in
            value.sorted { lhs, rhs in
                lhs.category.priority < rhs.category.priority
            }.first
        }
        let filtered = deduped.filter { $0.distance(from: location) <= radius }
        let sorted = filtered.sorted { lhs, rhs in
            let ld = lhs.distance(from: location)
            let rd = rhs.distance(from: location)
            if ld != rd { return ld < rd }
            return (lhs.name ?? "") < (rhs.name ?? "")
        }

        if sorted.isEmpty, outcome.hadNonTimeoutError {
            throw SmokingSpotSearchError.failed
        }

        return sorted
    }

    private func searchFirstAvailable(
        location: CLLocation,
        queries: [SearchQuery]
    ) async throws -> [SmokeModel.Spot] {
        for radius in config.radiiMeters {
            let spots = try await searchWithinRadius(location: location, radius: radius, queries: queries)
            if !spots.isEmpty {
                return spots
            }
        }
        return []
    }

    private static func search(
        query: String,
        center: SmokeModel.Coordinate,
        radius: CLLocationDistance,
        timeoutSeconds: TimeInterval,
        category: SmokeModel.SpotCategory
    ) async throws -> [SmokeModel.Spot] {
        try await withTimeout(seconds: timeoutSeconds) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(
                center: center.clCoordinate,
                latitudinalMeters: radius * 2,
                longitudinalMeters: radius * 2
            )

            let search = MKLocalSearch(request: request)

            let response = try await withTaskCancellationHandler(operation: {
                try await search.start()
            }, onCancel: {
                search.cancel()
            })

            return response.mapItems.compactMap { item in
                let coordinate = item.location.coordinate
                let coordinateStruct = SmokeModel.Coordinate(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
                return SmokeModel.Spot(name: item.name, coordinate: coordinateStruct, category: category)
            }
        }
    }

    private func queries(for category: SmokeModel.SpotCategory) -> [SearchQuery] {
        switch category {
        case .smokingSpot:
            return config.smokingSpotQueries.map {
                SearchQuery(text: $0, category: .smokingSpot)
            }
        case .cafe:
            return config.cafeQueries.map {
                SearchQuery(text: $0, category: .cafe)
            }
        }
    }

    private func queriesKey(for mode: SmokeModel.SearchMode, preference: SmokeModel.SpotCategory) -> String {
        "\(mode)-\(preference)"
    }

    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            defer { group.cancelAll() }

            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw SmokingSpotSearchError.timedOut
            }

            guard let result = try await group.next() else {
                throw CancellationError()
            }
            return result
        }
    }
}

private extension SmokeModel.SpotCategory {
    var priority: Int {
        switch self {
        case .smokingSpot:
            return 0
        case .cafe:
            return 1
        }
    }
}
