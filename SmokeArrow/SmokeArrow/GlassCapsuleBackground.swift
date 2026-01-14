import SwiftUI

struct GlassCapsuleBackground: View {
    let usesLightText: Bool

    var body: some View {
        let borderColor = usesLightText ? Color.white.opacity(0.28) : Color.black.opacity(0.10)
        let highlightOpacity = usesLightText ? 0.22 : 0.12
        let shadowOpacity = usesLightText ? 0.10 : 0.06

        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(highlightOpacity),
                                Color.white.opacity(0.02),
                                Color.white.opacity(0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.softLight)
            )
            .overlay(
                Capsule().strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 3, x: 0, y: 2)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        Text("理解しました")
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(GlassCapsuleBackground(usesLightText: false))
    }
}

