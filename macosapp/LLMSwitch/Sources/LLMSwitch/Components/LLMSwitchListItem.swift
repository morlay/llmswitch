import SwiftUI

struct LLMSwitchListItem<Content: View>: View {
    let spacing: CGFloat
    let verticalPadding: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        spacing: CGFloat = 10,
        verticalPadding: CGFloat = 0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.spacing = spacing
        self.verticalPadding = verticalPadding
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            content()
        }
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
