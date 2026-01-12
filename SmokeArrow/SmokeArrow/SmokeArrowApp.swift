//
//  SmokeArrowApp.swift
//  SmokeArrow
//
//  Created by 三瓶倫明 on 2026/01/11.
//

import GoogleMobileAds
import SwiftUI

@main
struct SmokeArrowApp: App {
    init() {
        let appID = (Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let appID, !appID.isEmpty, !appID.contains("$(") else {
            assertionFailure("GADApplicationIdentifier が Info.plist に設定されていません")
            return
        }

        if appID.contains("/") {
            assertionFailure("GADApplicationIdentifier に広告ユニットID形式(/)が入っています。App ID は ca-app-pub-xxxx~xxxx 形式です。")
        }

        let testDeviceIDs = AdMobConfig.testDeviceIdentifiers
        if !testDeviceIDs.isEmpty {
            MobileAds.shared.requestConfiguration.testDeviceIdentifiers = testDeviceIDs
            if AdMobConfig.isDiagnosticsEnabled {
                print("[AdMob] testDeviceIdentifiers set count=\(testDeviceIDs.count)")
            }
        } else if AdMobConfig.isDiagnosticsEnabled {
            print("[AdMob] testDeviceIdentifiers not set (ADMOB_TEST_DEVICE_IDS is empty)")
        }

        if AdMobConfig.isDiagnosticsEnabled {
            print("[AdMob] shouldUseTestAds=\(AdMobConfig.shouldUseTestAds) bannerAdUnitID=\(AdMobConfig.bannerAdUnitID)")
        }

        MobileAds.shared.start(completionHandler: nil)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
