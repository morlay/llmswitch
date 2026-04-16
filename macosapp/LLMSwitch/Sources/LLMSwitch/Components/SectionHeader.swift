import SwiftUI

struct SectionHeader<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toolbar {
                Text(title).font(.caption.weight(.medium))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) { content() }
        }
    }
}
