//
//  ContentView.swift
//  SmokeArrow
//
//  Created by 三瓶倫明 on 2026/01/11.
//

import SwiftUI
import UIKit
import Combine
import Foundation

struct ContentView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = NavigationViewModel()
    @State private var activeAlert: ActiveAlert?
    @State private var showMapPicker = false
    @State private var currentDate = Date()
    @AppStorage("arrowSymbolName") private var arrowSymbolName: String = "location.north.fill"
    @AppStorage("hasSeenSafetyNotice") private var hasSeenSafetyNotice: Bool = false
    @State private var isShowingSafetyNotice = false
    @State private var isCoreRunning = false
    private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private enum ScreenshotPreset: String {
        case one = "1"
        case two = "2"
        case three = "3"
        case four = "4"

        var spotName: String {
            switch self {
            case .one, .two, .three:
                "喫煙所"
            case .four:
                "どっち？カフェ"
            }
        }

        var meters: Double {
            switch self {
            case .one:
                149.6
            case .two:
                420
            case .three:
                650
            case .four:
                80
            }
        }

        var theme: BackgroundTheme {
            switch self {
            case .one:
                .morning
            case .two:
                .day
            case .three:
                .night
            case .four:
                .evening
            }
        }

        var arrowAngleDegrees: Double {
            switch self {
            case .one:
                35
            case .two:
                20
            case .three:
                65
            case .four:
                15
            }
        }

        var showsCafeSuggestionButton: Bool {
            switch self {
            case .three:
                true
            case .one, .two, .four:
                false
            }
        }

        var isCafeAlternative: Bool {
            switch self {
            case .four:
                true
            case .one, .two, .three:
                false
            }
        }

        var topTitleText: String {
            let trimmed = spotName.trimmingCharacters(in: .whitespacesAndNewlines)
            if isCafeAlternative {
                if trimmed.isEmpty {
                    return "喫煙可能なカフェ"
                }
                return "喫煙可能なカフェ：\(trimmed)"
            }
            return trimmed.isEmpty ? "喫煙所" : trimmed
        }

        var topSubtitleText: String {
            isCafeAlternative ? "喫煙可能なカフェも含めて検索中" : "喫煙所を探しています"
        }
    }

    private var screenshotPreset: ScreenshotPreset? {
        guard let raw = ProcessInfo.processInfo.environment["SCREENSHOT_PRESET"] else { return nil }
        return ScreenshotPreset(rawValue: raw)
    }

    private var isScreenshotMode: Bool { screenshotPreset != nil }

    private static let arrowSymbolCandidates: [String] = [
        "location.north.fill",
        "location.north",
        "location.north.circle.fill",
        "arrow.up.circle.fill",
    ]

    var body: some View {
        let theme = screenshotPreset?.theme ?? currentTheme
        let primaryColor = primaryForegroundColor(for: theme)
        let secondaryColor = secondaryForegroundColor(for: theme)
        let arrowAppearance = arrowAppearance(
            for: theme,
            distanceZone: distanceZoneForView,
            isAlternative: isShowingCafeAlternativeForView
        )
        ZStack {
            backgroundView(theme)
            VStack(spacing: 16) {
                Spacer(minLength: 0)

                ArrowView(
                    angleDegrees: arrowAngleDegreesForView,
                    isActive: isActiveForView,
                    symbolName: arrowSymbolName,
                    activeColor: arrowAppearance.activeColor,
                    inactiveColor: arrowAppearance.inactiveColor,
                    activeOpacity: arrowAppearance.activeOpacity
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    cycleArrowSymbol()
                }

                VStack(spacing: 4) {
                    Text(distanceTextForView)
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryColor)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)

                    if let detailText = distanceDetailText {
                        Text(detailText)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(secondaryColor)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24)
                .opacity(isActiveForView ? 1 : 0.35)

                permissionNotice(theme: theme, primaryColor: primaryColor, secondaryColor: secondaryColor)
                    .padding(.horizontal, 24)

                if let message = inlineStatusMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(secondaryColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if let cafeMessage = viewModel.cafeFallbackMessage {
                    Text(cafeMessage)
                        .font(.footnote)
                        .foregroundStyle(secondaryColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if shouldShowCafeSuggestionButtonForView {
                    Button {
                        guard !isScreenshotMode else { return }
                        viewModel.enableCafeSearch()
                    } label: {
                        Text("喫煙可能なカフェも探す")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(primaryColor)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                GlassCapsuleBackground(usesLightText: theme.usesLightText)
                            )
                    }
                    .padding(.top, 4)
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            topInset(foregroundColor: primaryColor)
                .safeAreaPadding(.top)
                .padding(.top, 8)
        }
        .overlay(alignment: .topTrailing) {
            infoButton(foregroundColor: primaryColor)
                .safeAreaPadding(.top)
                .padding(.top, 22)
                .padding(.trailing, 8)
        }
        .overlay(alignment: .bottom) {
            bottomInset()
                .safeAreaPadding(.bottom)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $isShowingSafetyNotice) {
            SafetyNoticeView(
                requiresAcknowledgement: !hasSeenSafetyNotice,
                usesLightText: theme.usesLightText,
                onAcknowledge: {
                    hasSeenSafetyNotice = true
                    isShowingSafetyNotice = false
                    startCoreIfAllowed()
                },
                onClose: {
                    isShowingSafetyNotice = false
                }
            )
            .presentationDetents([.fraction(0.4)])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("地図を選択", isPresented: $showMapPicker, titleVisibility: .visible) {
            Button("Apple マップ") { openMap(.apple) }
            Button("Google マップ") { openMap(.google) }
            Button("キャンセル", role: .cancel) {}
        }
        .alert(item: $activeAlert) { alert in
            switch alert.kind {
            case .notFound:
                return Alert(
                    title: Text("喫煙所が見つかりません"),
                    message: Text("付近に喫煙所が見つかりません（最大5km）。"),
                    primaryButton: .default(Text("再検索")) { viewModel.retrySearchNow() },
                    secondaryButton: .cancel(Text("OK"))
                )
            case .searchError:
                return Alert(
                    title: Text("検索に失敗しました"),
                    message: Text("通信状況を確認して、再検索してください。"),
                    primaryButton: .default(Text("再検索")) { viewModel.retrySearchNow() },
                    secondaryButton: .cancel(Text("OK"))
                )
            }
        }
        .onReceive(clock) { date in
            currentDate = date
        }
        .onAppear {
            currentDate = Date()
            startCoreIfAllowed()
        }
        .onDisappear {
            stopCoreIfNeeded()
        }
        .onChange(of: scenePhase) { oldValue, newValue in
            guard !isScreenshotMode else { return }
            switch newValue {
            case .active:
                currentDate = Date()
                startCoreIfAllowed()
                syncAlertWithState(force: true)
            case .background, .inactive:
                stopCoreIfNeeded()
                activeAlert = nil
                showMapPicker = false
            @unknown default:
                stopCoreIfNeeded()
            }
        }
        .onChange(of: viewModel.state) { oldValue, newValue in
            guard !isScreenshotMode else { return }
            syncAlertWithState()
        }
    }

    @ViewBuilder
    private func bottomInset() -> some View {
        AdBannerView()
            .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func topInset(foregroundColor: Color) -> some View {
        if let name = currentSpotDisplayNameForView {
            HStack(alignment: .top, spacing: 0) {
                Button {
                    guard !isScreenshotMode else { return }
                    showMapPicker = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label {
                            Text(name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(foregroundColor)

                        if let scopeMessage = searchScopeMessageForView {
                            Text(scopeMessage)
                                .font(.caption)
                                .foregroundStyle(foregroundColor.opacity(0.8))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)
            }
            .padding(.top, 14)
            .padding(.bottom, 6)
        } else if let scopeMessage = searchScopeMessageForView {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text(scopeMessage)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .font(.callout.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .padding(.top, 14)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private func infoButton(foregroundColor: Color) -> some View {
        Button {
            guard !isScreenshotMode else { return }
            isShowingSafetyNotice = true
        } label: {
            Image(systemName: "info.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(foregroundColor)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel("安全に関する注意")
    }

    private var inlineStatusMessage: String? {
        guard !isScreenshotMode else { return nil }
        switch viewModel.state {
        case .lowAccuracy:
            return "測位精度が低い可能性があります"
        default:
            return nil
        }
    }

    private var searchScopeMessage: String? {
        guard !isScreenshotMode else { return nil }
        switch viewModel.state {
        case .permissionNotDetermined, .permissionDenied, .notFound, .error, .locating:
            return nil
        case .searching, .navigating, .lowAccuracy:
            return switch viewModel.searchMode {
            case .smokingOnly:
                "喫煙所を探しています"
            case .includeCafe:
                "喫煙可能なカフェも含めて検索中"
            }
        }
    }

    private var distanceDetailText: String? {
        guard let meters = distanceMetersForView else { return nil }
        if isScreenshotMode {
            return DistanceDisplayFormatter.detailText(fromMeters: meters)
        }
        var lines = [DistanceDisplayFormatter.detailText(fromMeters: meters)]
        if searchModeForView == SmokeModel.SearchMode.includeCafe {
            lines.append("※ 喫煙可かは店舗により異なります")
        } else if shouldShowCafeSuggestionButtonForView {
            lines.append("（近くに喫煙所がありません）")
        }
        return lines.joined(separator: "\n")
    }

    private func applyWindowBackground() {
        DispatchQueue.main.async {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            for scene in scenes {
                for window in scene.windows {
                    window.backgroundColor = UIColor.clear
                    window.rootViewController?.view.backgroundColor = UIColor.clear
                }
            }
        }
    }

    private enum BackgroundTheme: String {
        case morning
        case day
        case evening
        case night
        case midnight

        var assetName: String { rawValue }

        var usesLightText: Bool {
            switch self {
            case .night, .midnight:
                return true
            case .morning, .day, .evening:
                return false
            }
        }
    }

    private var currentTheme: BackgroundTheme {
        Self.theme(for: currentDate)
    }

    private static func theme(for date: Date) -> BackgroundTheme {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<9:
            return .morning
        case 9..<17:
            return .day
        case 17..<20:
            return .evening
        case 20..<24:
            return .night
        default:
            return .midnight
        }
    }

    @ViewBuilder
    private func backgroundView(_ theme: BackgroundTheme) -> some View {
        Image(theme.assetName)
            .resizable()
            .scaledToFill()
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    private func primaryForegroundColor(for theme: BackgroundTheme) -> Color {
        theme.usesLightText ? .white : .primary
    }

    private func secondaryForegroundColor(for theme: BackgroundTheme) -> Color {
        theme.usesLightText ? Color.white.opacity(0.7) : .secondary
    }

    private struct ArrowAppearance {
        let activeColor: Color
        let inactiveColor: Color
        let activeOpacity: Double
    }

    private func arrowAppearance(
        for theme: BackgroundTheme,
        distanceZone: DistanceDisplayFormatter.DistanceZone?,
        isAlternative: Bool
    ) -> ArrowAppearance {
        let baseColor: Color = theme.usesLightText ? .white : .primary
        let greyColor: Color = theme.usesLightText ? Color.white.opacity(0.7) : Color.gray
        let inactiveColor: Color = theme.usesLightText ? Color.white.opacity(0.5) : .secondary

        let isHesitant = distanceZone == .hesitant
        let isFar = distanceZone == .far
            || distanceZone == .outOfRange
            || distanceZone == .outOfRangeLong

        let activeColor = (isAlternative || isFar) ? greyColor : baseColor
        let activeOpacity: Double = isAlternative ? 0.65 : (isFar ? 0.6 : (isHesitant ? 0.85 : 1))

        return ArrowAppearance(activeColor: activeColor, inactiveColor: inactiveColor, activeOpacity: activeOpacity)
    }

    private enum MapProvider {
        case apple
        case google
    }

    private func openMap(_ provider: MapProvider) {
        guard let target = viewModel.currentTarget else { return }
        showMapPicker = false

        let rawName = target.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = viewModel.isShowingCafeAlternative ? "喫煙可能なカフェ" : "喫煙所"
        let name = (rawName?.isEmpty == false) ? rawName ?? fallbackName : fallbackName
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? fallbackName
        let lat = target.coordinate.latitude
        let lon = target.coordinate.longitude

        switch provider {
        case .apple:
            if let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lon)&q=\(encodedName)") {
                openURL(url)
            }
        case .google:
            let appURL = URL(string: "comgooglemaps://?q=\(lat),\(lon)")
            let webURL = URL(string: "https://www.google.com/maps/search/?api=1&query=\(lat),\(lon)")
            if let appURL {
                openURL(appURL) { accepted in
                    if !accepted, let webURL {
                        openURL(webURL)
                    }
                }
            } else if let webURL {
                openURL(webURL)
            }
        }
    }

    private func syncAlertWithState(force: Bool = false) {
        let kind: ActiveAlert.Kind? = switch viewModel.state {
        case .notFound:
            .notFound
        case .error:
            .searchError
        default:
            nil
        }

        guard let kind else { return }
        if force || activeAlert?.kind != kind {
            activeAlert = ActiveAlert(kind: kind)
        }
    }

    private func cycleArrowSymbol() {
        let candidates = Self.arrowSymbolCandidates
        guard !candidates.isEmpty else { return }
        let currentIndex = candidates.firstIndex(of: arrowSymbolName) ?? 0
        let nextIndex = (currentIndex + 1) % candidates.count
        arrowSymbolName = candidates[nextIndex]
    }

    private func startCoreIfAllowed() {
        guard !isScreenshotMode else { return }
        if !hasSeenSafetyNotice {
            isShowingSafetyNotice = true
            return
        }
        guard !isCoreRunning else { return }
        isCoreRunning = true
        viewModel.onAppear()
        applyWindowBackground()
    }

    private func stopCoreIfNeeded() {
        guard !isScreenshotMode else { return }
        guard isCoreRunning else { return }
        isCoreRunning = false
        viewModel.onDisappear()
    }

    private var distanceMetersForView: Double? {
        if let preset = screenshotPreset { return preset.meters }
        return viewModel.distanceMeters
    }

    private var distanceZoneForView: DistanceDisplayFormatter.DistanceZone? {
        if let meters = distanceMetersForView {
            return DistanceDisplayFormatter.presentation(fromMeters: meters).zone
        }
        return viewModel.distanceZone
    }

    private var distanceTextForView: String {
        if let meters = distanceMetersForView {
            return DistanceDisplayFormatter.presentation(fromMeters: meters).text
        }
        return viewModel.distanceText
    }

    private var arrowAngleDegreesForView: Double? {
        if let preset = screenshotPreset { return preset.arrowAngleDegrees }
        return viewModel.arrowAngleDegrees
    }

    private var isActiveForView: Bool {
        if isScreenshotMode { return true }
        return viewModel.state == .navigating || viewModel.state == .lowAccuracy
    }

    private var currentSpotDisplayNameForView: String? {
        if let preset = screenshotPreset { return preset.topTitleText }
        return viewModel.currentSpotDisplayName
    }

    private var searchModeForView: SmokeModel.SearchMode {
        if let preset = screenshotPreset { return preset.isCafeAlternative ? .includeCafe : .smokingOnly }
        return viewModel.searchMode
    }

    private var shouldShowCafeSuggestionButtonForView: Bool {
        if let preset = screenshotPreset { return preset.showsCafeSuggestionButton }
        return viewModel.shouldShowCafeSuggestionButton
    }

    private var isShowingCafeAlternativeForView: Bool {
        if let preset = screenshotPreset { return preset.isCafeAlternative }
        return viewModel.isShowingCafeAlternative
    }

    private var searchScopeMessageForView: String? {
        if let preset = screenshotPreset { return preset.topSubtitleText }
        return searchScopeMessage
    }

    @ViewBuilder
    private func permissionNotice(theme: BackgroundTheme, primaryColor: Color, secondaryColor: Color) -> some View {
        if isScreenshotMode {
            EmptyView()
        } else {
            switch viewModel.state {
            case .permissionNotDetermined:
                VStack(spacing: 12) {
                    Text("周辺の喫煙所を検索し、方向と距離を表示するために位置情報を使用します。")
                        .font(.footnote)
                        .foregroundStyle(secondaryColor)
                        .multilineTextAlignment(.center)
                    Button {
                        viewModel.requestAuthorization()
                    } label: {
                        Text("現在位置を許可")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(primaryColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(GlassCapsuleBackground(usesLightText: theme.usesLightText))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            case .permissionDenied:
                VStack(spacing: 12) {
                    Text("位置情報がオフのため周辺検索が使えません")
                        .font(.footnote)
                        .foregroundStyle(secondaryColor)
                        .multilineTextAlignment(.center)
                    Button {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    } label: {
                        Text("設定を開く")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(primaryColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(GlassCapsuleBackground(usesLightText: theme.usesLightText))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            case .locating:
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(primaryColor)
                    Text("現在地を取得しています…")
                        .font(.footnote)
                        .foregroundStyle(secondaryColor)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            default:
                EmptyView()
            }
        }
    }
}

#Preview {
    ContentView()
}

private struct ActiveAlert: Identifiable {
    enum Kind: Equatable {
        case notFound
        case searchError
    }

    let id = UUID()
    let kind: Kind
}
