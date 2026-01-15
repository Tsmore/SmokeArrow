import GoogleMobileAds
import SwiftUI
import UIKit

enum AdMobConfig {
    static let productionBannerAdUnitID = "ca-app-pub-1008247845650686/9450025669"
    static let testBannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"

    static var bannerAdUnitID: String {
        shouldUseTestAds ? testBannerAdUnitID : productionBannerAdUnitID
    }

    static var shouldUseTestAds: Bool {
#if DEBUG
        return true
#else
        if ProcessInfo.processInfo.environment["ADMOB_FORCE_TEST_ADS"] == "1" {
            return true
        }
        if ProcessInfo.processInfo.environment["ADMOB_FORCE_PRODUCTION_ADS"] == "1" {
            return false
        }
        // Release / TestFlight では基本的に本番広告を使う（テスト広告は明示的に強制したときのみ）
        return false
#endif
    }

    static var isDiagnosticsEnabled: Bool {
        shouldUseTestAds || ProcessInfo.processInfo.environment["ADMOB_LOGS"] == "1"
    }

    static var testDeviceIdentifiers: [String] {
        guard let raw = ProcessInfo.processInfo.environment["ADMOB_TEST_DEVICE_IDS"] else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

struct AdMobBannerView: UIViewControllerRepresentable {
    let adUnitID: String

    func makeUIViewController(context: Context) -> BannerViewController {
        BannerViewController(adUnitID: adUnitID)
    }

    func updateUIViewController(_ uiViewController: BannerViewController, context: Context) {
        uiViewController.updateAdUnitIDIfNeeded(adUnitID)
    }
}

final class BannerViewController: UIViewController {
    private let bannerView = BannerView(adSize: AdSizeBanner)
    private var currentAdUnitID: String
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var lastAdSize: AdSize?
    private var hasLoadedOnce = false

    init(adUnitID: String) {
        self.currentAdUnitID = BannerViewController.normalizeBannerAdUnitID(adUnitID)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        bannerView.adUnitID = currentAdUnitID
        bannerView.rootViewController = self
        bannerView.delegate = self

        view.addSubview(bannerView)
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        widthConstraint = bannerView.widthAnchor.constraint(equalToConstant: AdSizeBanner.size.width)
        heightConstraint = bannerView.heightAnchor.constraint(equalToConstant: AdSizeBanner.size.height)
        widthConstraint?.isActive = true
        heightConstraint?.isActive = true
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateAdSizeAndReloadIfNeeded()
    }

    func updateAdUnitIDIfNeeded(_ adUnitID: String) {
        let normalized = BannerViewController.normalizeBannerAdUnitID(adUnitID)
        guard currentAdUnitID != normalized else { return }
        currentAdUnitID = normalized
        bannerView.adUnitID = normalized
        reload(reason: "adUnitID updated")
    }
}

extension BannerViewController: BannerViewDelegate {
    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        log("didReceiveAd adUnitID=\(currentAdUnitID) responseInfo=\(String(describing: bannerView.responseInfo))")
    }

    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        log("didFailToReceiveAd adUnitID=\(currentAdUnitID) error=\(error) responseInfo=\(String(describing: bannerView.responseInfo))")
    }
}

private extension BannerViewController {
    static func normalizeBannerAdUnitID(_ adUnitID: String) -> String {
        let trimmed = adUnitID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return AdMobConfig.testBannerAdUnitID }
        return trimmed
    }

    func log(_ message: String) {
        guard AdMobConfig.isDiagnosticsEnabled else { return }
        print("[AdMob] \(message)")
    }

    func updateAdSizeAndReloadIfNeeded() {
        let availableWidth = max(0, view.bounds.inset(by: view.safeAreaInsets).width)
        guard availableWidth > 0 else { return }

        let adSize = currentOrientationAnchoredAdaptiveBanner(width: availableWidth)
        if let lastAdSize, lastAdSize.size.width == adSize.size.width, lastAdSize.size.height == adSize.size.height {
            if !hasLoadedOnce {
                reload(reason: "initial load")
            }
            return
        }

        lastAdSize = adSize
        bannerView.adSize = adSize
        widthConstraint?.constant = adSize.size.width
        heightConstraint?.constant = adSize.size.height
        reload(reason: "adSize updated to \(Int(adSize.size.width))x\(Int(adSize.size.height)) (availableWidth=\(Int(availableWidth)))")
    }

    func reload(reason: String) {
        log("load start (\(reason)) adUnitID=\(currentAdUnitID) adSize=\(Int(bannerView.adSize.size.width))x\(Int(bannerView.adSize.size.height))")
        hasLoadedOnce = true
        bannerView.load(Request())
    }
}

#Preview {
    VStack {
        Spacer()
        AdMobBannerView(adUnitID: AdMobConfig.testBannerAdUnitID)
            .frame(height: 50)
    }
}
