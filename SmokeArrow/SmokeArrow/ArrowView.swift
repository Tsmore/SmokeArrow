import SwiftUI

struct ArrowView: View {
    let angleDegrees: Double?
    let isActive: Bool
    let symbolName: String
    let activeColor: Color
    let inactiveColor: Color
    let activeOpacity: Double
    let inactiveOpacity: Double

    init(
        angleDegrees: Double?,
        isActive: Bool,
        symbolName: String = "location.north.fill",
        activeColor: Color = .primary,
        inactiveColor: Color = .secondary,
        activeOpacity: Double = 1,
        inactiveOpacity: Double = 0.25
    ) {
        self.angleDegrees = angleDegrees
        self.isActive = isActive
        self.symbolName = symbolName
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.activeOpacity = activeOpacity
        self.inactiveOpacity = inactiveOpacity
    }

    var body: some View {
        Image(systemName: symbolName)
            .resizable()
            .scaledToFit()
            .frame(width: 160, height: 160)
            .rotationEffect(.degrees(angleDegrees ?? 0))
            .foregroundStyle(isActive ? activeColor : inactiveColor)
            .opacity(isActive ? activeOpacity : inactiveOpacity)
            .animation(.linear(duration: 0.12), value: angleDegrees ?? 0)
    }
}

#Preview {
    VStack(spacing: 24) {
        ArrowView(angleDegrees: 0, isActive: true, symbolName: "location.north.fill")
        ArrowView(angleDegrees: 120, isActive: true, symbolName: "arrowtriangle.up.fill")
        ArrowView(angleDegrees: nil, isActive: false, symbolName: "paperplane.fill")
    }
    .padding()
}
