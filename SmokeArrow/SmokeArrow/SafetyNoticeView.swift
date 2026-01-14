import SwiftUI

struct SafetyNoticeView: View {
    let requiresAcknowledgement: Bool
    let usesLightText: Bool
    let onAcknowledge: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("本アプリの目的（ルール遵守）を明確にするため、以下をご確認ください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("・喫煙は健康に悪影響を及ぼします")
                        Text("・本アプリは喫煙を推奨するものではなく、指定喫煙エリアへの誘導により禁煙エリアでの喫煙を避けることを目的としています")
                        Text("・法令、施設のルール、現地の案内表示に従ってください")
                        Text("・未成年の喫煙は法律で禁止されています")
                    }
                    .font(.body)
                    .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        onAcknowledge()
                    } label: {
                        Text("理解しました")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(GlassCapsuleBackground(usesLightText: usesLightText))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
            }
            .navigationTitle("安全に関する注意")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !requiresAcknowledgement {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            onClose()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(requiresAcknowledgement)
    }
}

#Preview {
    SafetyNoticeView(
        requiresAcknowledgement: true,
        usesLightText: false,
        onAcknowledge: {},
        onClose: {}
    )
}
