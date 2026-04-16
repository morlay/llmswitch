import SwiftUI

struct LLMSwitchCard<Content: View>: View {
    let padding: CGFloat
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        padding: CGFloat = 12,
        cornerRadius: CGFloat = 10,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
