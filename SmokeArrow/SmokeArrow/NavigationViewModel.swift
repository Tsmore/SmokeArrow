import Combine
import CoreLocation
import Foundation

@MainActor
final class NavigationViewModel: ObservableObject {
    private enum CafePreference {
        case smokingFirst
        case cafeFirst
    }

    enum CoreState: Equatable {
        case permissionNotDetermined
        case permissionDenied
        case locating
        case searching
        case navigating
        case lowAccuracy
        case notFound
        case error
    }

    @Published private(set) var state: CoreState = .permissionNotDetermined
    @Published private(set) var arrowAngleDegrees: Double?
    @Published private(set) var distanceText: String = "--"
    @Published private(set) var distanceZone: DistanceDisplayFormatter.DistanceZone?
    @Published private(set) var distanceMeters: CLLocationDistance?

    private let locationService: LocationService
    private let searchService: SmokingSpotSearchService

    @Published private(set) var currentTarget: SmokeModel.Spot?
    @Published private(set) var searchMode: SmokeModel.SearchMode = .smokingOnly
    private var isSearching = false
    private var hasNoResults = false
    private var lastSearchFailed = false
    private var consecutiveSearchFailures = 0
    private var shouldForceTargetUpdate = false
    private var cafePreference: CafePreference = .smokingFirst

    private var lastSearchLocation: CLLocation?
    private var lastSearchDate: Date?
    private var lastSearchAccuracy: CLLocationAccuracy?
    private var lastSearchMode: SmokeModel.SearchMode?

    private var smoothedRelativeAngleDegrees: Double?
    private var lastAngleUpdateUptime: TimeInterval?

    private let fastTickNanoseconds: UInt64 = 100_000_000
    private let slowTickNanoseconds: UInt64 = 500_000_000
    private let headingSmoothingTime: TimeInterval = 0.1

    private var tickTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init() {
        self.locationService = LocationService()
        self.searchService = SmokingSpotSearchService()
        updateState()
    }

    init(locationService: LocationService, searchService: SmokingSpotSearchService) {
        self.locationService = locationService
        self.searchService = searchService
        updateState()
    }

    var statusMessage: String? {
        switch state {
        case .permissionNotDetermined:
            return "位置情報を許可してください"
        case .permissionDenied:
            return "位置情報が許可されていません（設定で変更できます）"
        case .locating:
            return "測位中…"
        case .searching:
            return "検索中…"
        case .lowAccuracy:
            return "測位精度が低い可能性があります"
        case .notFound:
            return "付近に喫煙所が見つかりません（最大5km）"
        case .error:
            return "検索に失敗しました"
        case .navigating:
            return nil
        }
    }

    var shouldShowPermissionButton: Bool {
        state == .permissionNotDetermined
    }

    var shouldShowSettingsButton: Bool {
        state == .permissionDenied
    }

    var shouldShowRetryButton: Bool {
        state == .error || state == .notFound
    }

    var shouldShowCafeSuggestionButton: Bool {
        guard searchMode == SmokeModel.SearchMode.smokingOnly else { return false }
        guard let distanceZone else { return false }
        switch distanceZone {
        case .hesitant, .far, .outOfRange, .outOfRangeLong:
            return true
        default:
            return false
        }
    }

    var isShowingCafeAlternative: Bool {
        currentTarget?.category == SmokeModel.SpotCategory.cafe
    }

    var currentSpotDisplayName: String? {
        guard let currentTarget else { return nil }
        let trimmed = currentTarget.name?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        switch currentTarget.category {
        case .cafe:
            if let trimmed, !trimmed.isEmpty {
                return "喫煙可能なカフェ：\(trimmed)"
            }
            return "喫煙可能なカフェ"
        case .smokingSpot:
            if let trimmed, !trimmed.isEmpty {
                return trimmed
            }
            return "喫煙所"
        }
    }

    var cafeFallbackMessage: String? {
        guard searchMode == SmokeModel.SearchMode.includeCafe else { return nil }
        guard let distanceZone else { return nil }
        switch distanceZone {
        case .outOfRange, .outOfRangeLong:
            return "カフェも候補に追加しています"
        default:
            return nil
        }
    }

    func onAppear() {
        locationService.start()
        refresh()
        startTick()
    }

    func onDisappear() {
        tickTask?.cancel()
        searchTask?.cancel()
        locationService.stop()
    }

    func requestAuthorization() {
        locationService.requestAuthorizationIfNeeded()
    }

    func retrySearchNow() {
        guard locationService.isAuthorized else { return }
        guard let location = locationService.location else { return }
        startSearch(from: location)
    }

    func enableCafeSearch() {
        guard searchMode == SmokeModel.SearchMode.smokingOnly else { return }
        searchMode = SmokeModel.SearchMode.includeCafe
        cafePreference = .cafeFirst
        shouldForceTargetUpdate = true
        guard let location = locationService.location else { return }
        startSearch(from: location)
    }

    private func startTick() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                let interval = self.isHighFrequencyUpdate ? self.fastTickNanoseconds : self.slowTickNanoseconds
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func refresh() {
        updateState()

        guard locationService.isAuthorized else {
            resetGuidance()
            return
        }
        guard let location = locationService.location else {
            resetGuidance()
            return
        }

        if shouldStartSearch(currentLocation: location) {
            startSearch(from: location)
        }

        updateGuidance(currentLocation: location)
        updateState()
    }

    private func updateState() {
        switch locationService.authorizationStatus {
        case .notDetermined:
            state = .permissionNotDetermined
        case .restricted, .denied:
            state = .permissionDenied
        case .authorizedAlways, .authorizedWhenInUse:
            if locationService.location == nil {
                state = .locating
            } else if currentTarget != nil {
                state = isLowAccuracy() ? .lowAccuracy : .navigating
            } else if isSearching {
                state = .searching
            } else if lastSearchFailed {
                state = .error
            } else if hasNoResults {
                state = .notFound
            } else {
                state = .searching
            }
        @unknown default:
            state = .permissionDenied
        }
    }

    private func shouldStartSearch(currentLocation: CLLocation) -> Bool {
        guard !isSearching else { return false }

        guard let lastSearchLocation, let lastSearchDate else {
            return true
        }

        let moved = currentLocation.distance(from: lastSearchLocation) >= 50
        let elapsed = Date().timeIntervalSince(lastSearchDate) >= 60
        let retryAfterFailure = lastSearchFailed && shouldRetryAfterFailure(lastSearchDate: lastSearchDate)
        let modeChanged = lastSearchMode != searchMode

        let improvedAccuracy: Bool = {
            guard
                let lastSearchAccuracy,
                currentLocation.horizontalAccuracy >= 0,
                lastSearchAccuracy >= 0
            else { return false }
            return currentLocation.horizontalAccuracy <= (lastSearchAccuracy - 20)
        }()

        return moved || elapsed || improvedAccuracy || retryAfterFailure || modeChanged
    }

    private func startSearch(from location: CLLocation) {
        searchTask?.cancel()
        isSearching = true
        lastSearchFailed = false
        hasNoResults = false

        lastSearchLocation = location
        lastSearchDate = Date()
        lastSearchAccuracy = location.horizontalAccuracy
        lastSearchMode = searchMode

        let locationSnapshot = location
        let modeSnapshot = searchMode
        let preferenceSnapshot: SmokeModel.SpotCategory = switch cafePreference {
        case .cafeFirst:
            .cafe
        case .smokingFirst:
            .smokingSpot
        }
        searchTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    self.isSearching = false
                    self.searchTask = nil
                }
            }

            do {
                let spots = try await self.searchService.searchNearestSpots(
                    from: locationSnapshot,
                    mode: modeSnapshot,
                    preference: preferenceSnapshot
                )
                await MainActor.run {
                    self.lastSearchFailed = false
                    self.hasNoResults = spots.isEmpty
                    self.consecutiveSearchFailures = 0
                    self.updateTarget(spots: spots, userLocation: self.locationService.location ?? locationSnapshot)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self.lastSearchFailed = true
                    self.hasNoResults = false
                    self.consecutiveSearchFailures += 1
                }
            }
        }
    }

    private func shouldRetryAfterFailure(lastSearchDate: Date) -> Bool {
        let base: TimeInterval = 5
        let exponent = max(0, consecutiveSearchFailures - 1)
        let interval = min(60, base * pow(2, Double(exponent)))
        return Date().timeIntervalSince(lastSearchDate) >= interval
    }

    private func updateTarget(spots: [SmokeModel.Spot], userLocation: CLLocation) {
        guard let newNearest = preferredTarget(from: spots, userLocation: userLocation) else {
            currentTarget = nil
            shouldForceTargetUpdate = false
            return
        }

        guard let currentTarget else {
            self.currentTarget = newNearest
            shouldForceTargetUpdate = false
            return
        }

        if shouldForceTargetUpdate {
            self.currentTarget = newNearest
            shouldForceTargetUpdate = false
            return
        }

        let currentDistance = currentTarget.distance(from: userLocation)
        let newDistance = newNearest.distance(from: userLocation)

        if newDistance <= currentDistance * 0.9 {
            self.currentTarget = newNearest
        }
    }

    private func preferredTarget(from spots: [SmokeModel.Spot], userLocation: CLLocation) -> SmokeModel.Spot? {
        guard !spots.isEmpty else { return nil }
        return spots.min(by: { lhs, rhs in
            lhs.distance(from: userLocation) < rhs.distance(from: userLocation)
        })
    }

    private func updateGuidance(currentLocation: CLLocation) {
        guard let currentTarget else {
            resetGuidance()
            return
        }

        let distance = currentTarget.distance(from: currentLocation)
        distanceMeters = distance
        let presentation = DistanceDisplayFormatter.presentation(fromMeters: distance)
        distanceZone = presentation.zone
        if distanceText != presentation.text {
            distanceText = presentation.text
        }

        guard let heading = locationService.bestHeadingDegrees else {
            arrowAngleDegrees = nil
            smoothedRelativeAngleDegrees = nil
            return
        }

        let user = SmokeModel.Coordinate(
            latitude: currentLocation.coordinate.latitude,
            longitude: currentLocation.coordinate.longitude
        )
        let bearing = GeoMath.bearingDegrees(from: user, to: currentTarget.coordinate)
        let relative = GeoMath.normalize180(bearing - heading)
        let now = ProcessInfo.processInfo.systemUptime
        let deltaTime = lastAngleUpdateUptime.map { now - $0 } ?? 0
        lastAngleUpdateUptime = now
        let smoothed = GeoMath.smoothAngleDegrees(
            previous: smoothedRelativeAngleDegrees,
            next: relative,
            deltaTime: deltaTime,
            smoothingTime: headingSmoothingTime
        )

        smoothedRelativeAngleDegrees = smoothed
        arrowAngleDegrees = smoothed
    }

    private func resetGuidance() {
        arrowAngleDegrees = nil
        distanceText = "--"
        distanceZone = nil
        distanceMeters = nil
        smoothedRelativeAngleDegrees = nil
        lastAngleUpdateUptime = nil
    }

    private var isHighFrequencyUpdate: Bool {
        state == .navigating || state == .lowAccuracy
    }

    private func isLowAccuracy() -> Bool {
        guard let location = locationService.location else { return true }

        if location.horizontalAccuracy < 0 {
            return true
        }
        if location.horizontalAccuracy > 65 {
            return true
        }

        if let heading = locationService.heading {
            if heading.headingAccuracy < 0 {
                return true
            }
            if heading.headingAccuracy > 25 {
                return true
            }
        } else if locationService.bestHeadingDegrees == nil {
            return true
        }

        return false
    }
}
