import SwiftUI

struct LLMSwitchToolbar<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        spacing: CGFloat = 10,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            content()
        }
    }
}
