import SwiftUI

struct Toolbar<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { HStack(spacing: 10) { content() } }
}
