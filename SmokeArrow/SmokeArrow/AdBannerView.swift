import SwiftUI

struct AdBannerView: View {
    var adUnitID: String = AdMobConfig.bannerAdUnitID

    var body: some View {
        AdMobBannerView(adUnitID: adUnitID)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
    }
}

#Preview {
    VStack {
        Spacer()
        AdBannerView(adUnitID: AdMobConfig.testBannerAdUnitID)
    }
}
